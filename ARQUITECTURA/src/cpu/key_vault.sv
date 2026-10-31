// =============================================================================
// key_vault.sv  -  Bóveda de llaves (Root of Trust) de CERBERO
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
// -----------------------------------------------------------------------------
// Implementa la sección 8 del isa.md (commit 24b0b17):
//   - 4 llaves de 128 bits (4 subllaves de 32 bits c/u) + KVALID[3:0]
//   - Registro de desafío de 128 bits, SOLO escritura (AUTHW)
//   - ROT_SECRET de 128 bits (password_reg), valor inicial por parámetro
//   - Instrucciones del slot S3:  KSETW, AUTHW, VCTL (LOGIN/LOGOUT/PWSET/KCLR)
//   - Lectura de subllave para F4E/F4D (única salida de datos de la bóveda)
//   - Bits AUTH / AUTHFAIL hacia el PSW
//   - Auto-logout: falla en cualquier slot o PC fuera de [SEC_BASE, SEC_LIMIT]
//
// Modelo de temporización (independiente de la etapa del pipeline):
//   - Todo lo que se REVISA o se LEE es combinacional (subkey, grant, fault).
//   - Todo lo que CAMBIA estado ocurre en un único flanco de subida de clk.
//   - La operación ve el estado PREVIO al bundle (mismo criterio que el regfile).
//
// Decisiones no definidas en isa.md (documentar en microarchitecture.md):
//   D1. AUTHW usa widx en [10:9]; [12:11] es reservado (=0).
//   D2. LOGIN/LOGOUT/PWSET exigen [10:9]=0; KCLR usa kv en [10:9].
//   D3. LOGIN limpia el desafío tras comparar (éxito o fallo).
//       Éxito: AUTH=1, AUTHFAIL=0. Fallo: AUTH=0, AUTHFAIL=1.
//   D4. LOGIN fuera de la región segura se acepta, pero AUTH cae en el mismo
//       flanco por la regla de auto-logout (en la práctica no abre sesión).
//   D5. KVALID[k] = las 4 palabras de la llave k fueron escritas (máscara).
//       Reescribir una palabra de una llave válida la mantiene válida.
//   D6. PWSET copia el desafío a ROT_SECRET y luego limpia el desafío.
//   D7. Las operaciones privilegiadas (KSETW, PWSET, KCLR, F4E, F4D) exigen
//       AUTH=1 Y que la propia instrucción esté en la región segura.
//   D8. fault_any (falla en otro slot del mismo bundle) NO anula la op del
//       vault (las fallas anulan solo su slot), pero sí limpia AUTH. Si
//       coincide con un LOGIN exitoso, gana la falla: AUTH queda en 0.
//   D9. El opcode 111 de S3 (reservado) lo marca como ILLOP quien decodifique
//       S3 completo; el vault solo reconoce 001..101.
// =============================================================================

`include "cerbero_defs.svh"

module key_vault #(
    parameter logic [127:0] ROT_SECRET_INIT = 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210,
    parameter logic [31:0]  SEC_BASE        = `SEC_BASE_DEF,
    parameter logic [31:0]  SEC_LIMIT       = `SEC_LIMIT_DEF
)(
    input  logic        clk,
    input  logic        rst_n,          // reset síncrono, activo en bajo

    // ---- Entrada desde el slot S3 -----------------------------------------
    input  logic        valid,          // hay un bundle válido en esta etapa
    input  logic [15:0] slot,           // bits [31:16] del bundle (S3 crudo)
    input  logic [31:0] rs_data,        // R[rs] (KSETW / AUTHW)
    input  logic [31:0] pc,             // PC del bundle que trae esta op
    input  logic        fault_any,      // falla en otro slot del mismo bundle

    // ---- Hacia crypto_unit -------------------------------------------------
    output logic [31:0] subkey,         // VAULT[kv][ronda]; 0 si grant=0
    output logic        grant,          // 1 = la ronda F4E/F4D puede ejecutarse

    // ---- Hacia PSW ---------------------------------------------------------
    output logic        fault,          // esta op del vault falló
    output logic [2:0]  cause,          // ILLOP / DENIED / NOKEY
    output logic        auth,           // PSW[4]
    output logic        authfail,       // PSW[5]
    output logic [3:0]  kvalid          // estado de ranuras (no es dato secreto)
);

    // -------------------------------------------------------------------------
    // Constantes del ISA, derivadas de cerbero_defs.svh.
    //
    // Los nombres locales se conservan porque hacen legible el cuerpo del
    // modulo, pero los numeros vienen del archivo de definiciones: renumerar
    // un opcode se hace en un solo lugar y el RTL y los testbenches quedan
    // sincronizados.
    // -------------------------------------------------------------------------
    localparam logic [2:0] OP_F4E   = `CRP_F4E;
    localparam logic [2:0] OP_F4D   = `CRP_F4D;
    localparam logic [2:0] OP_KSETW = `CRP_KSETW;
    localparam logic [2:0] OP_AUTHW = `CRP_AUTHW;
    localparam logic [2:0] OP_VCTL  = `CRP_VCTL;

    localparam logic [1:0] FN_LOGIN  = `VCTL_LOGIN;
    localparam logic [1:0] FN_LOGOUT = `VCTL_LOGOUT;
    localparam logic [1:0] FN_PWSET  = `VCTL_PWSET;
    localparam logic [1:0] FN_KCLR   = `VCTL_KCLR;

    localparam logic [2:0] C_NONE   = `CAUSE_NONE;
    localparam logic [2:0] C_ILLOP  = `CAUSE_ILLOP;
    localparam logic [2:0] C_DENIED = `CAUSE_DENIED;
    localparam logic [2:0] C_NOKEY  = `CAUSE_NOKEY;

    // -------------------------------------------------------------------------
    // Estado interno. NINGUNO de estos registros tiene ruta hacia una salida
    // salvo vault_mem -> subkey (y solo cuando grant=1).
    // -------------------------------------------------------------------------
    logic [31:0]  vault_mem [0:3][0:3];   // [llave][palabra]
    logic [3:0]   wmask     [0:3];        // palabras escritas por llave
    logic [127:0] challenge;              // desafío (solo escritura)
    logic [127:0] password_reg;           // ROT_SECRET
    logic         auth_q, authfail_q;

    // -------------------------------------------------------------------------
    // Decodificación de campos (formatos F y V, isa.md 2.5)
    // -------------------------------------------------------------------------
    logic [2:0] opc;
    logic [1:0] fA, fB;          // [12:11] y [10:9] (tipo V)
    logic [1:0] f_kv, f_ronda;   // tipo F
    assign opc     = slot[`S3_OPC];
    assign fA      = slot[`S3_FLD_A];
    assign fB      = slot[`S3_FLD_B];
    assign f_kv    = slot[`S3_KV];
    assign f_ronda = slot[`S3_RONDA];

    logic is_f4, is_ksetw, is_authw, is_vctl;
    assign is_f4    = valid && (opc == OP_F4E || opc == OP_F4D);
    assign is_ksetw = valid && (opc == OP_KSETW);
    assign is_authw = valid && (opc == OP_AUTHW);
    assign is_vctl  = valid && (opc == OP_VCTL);

    logic is_login, is_logout, is_pwset, is_kclr;
    assign is_login  = is_vctl && (fA == FN_LOGIN);
    assign is_logout = is_vctl && (fA == FN_LOGOUT);
    assign is_pwset  = is_vctl && (fA == FN_PWSET);
    assign is_kclr   = is_vctl && (fA == FN_KCLR);

    // Bits reservados distintos de cero -> ILLOP (isa.md 2.6)
    // (assign en vez de always_comb: Icarus 12 no soporta part-selects
    //  constantes dentro de always_* y lanza warnings.)
    logic illop;
    assign illop = is_f4    ? (slot[5:0]  != 6'd0)                    :
                   is_ksetw ? (slot[4:0]  != 5'd0)                    :
                   is_authw ? ((slot[4:0] != 5'd0) || (fA != 2'd0))   :
                   is_kclr  ? (slot[8:0]  != 9'd0)                    :  // kv en [10:9]
                   is_vctl  ? (slot[10:0] != 11'd0)                   :  // LOGIN/LOGOUT/PWSET
                              1'b0;
    // En VCTL el campo rs [8:5] no se usa, así que también debe ir en cero.

    // -------------------------------------------------------------------------
    // Control de acceso
    // -------------------------------------------------------------------------
    logic in_secure;
    assign in_secure = (pc >= SEC_BASE) && (pc <= SEC_LIMIT);

    logic priv_ok;               // sesión abierta y código en la región segura
    assign priv_ok = auth_q && in_secure;

    logic is_priv;               // operaciones que exigen AUTH
    assign is_priv = is_f4 || is_ksetw || is_pwset || is_kclr;

    // Selección de llave para F4 / KSETW / KCLR
    logic [1:0] kv_sel;
    assign kv_sel = is_f4 ? f_kv : (is_ksetw ? fA : fB);

    always_comb begin
        cause = C_NONE;
        if (illop)                              cause = C_ILLOP;
        else if (is_priv && !priv_ok)           cause = C_DENIED;
        else if (is_f4 && !(&wmask[kv_sel]))    cause = C_NOKEY;
    end
    assign fault = (cause != C_NONE);

    // Una op del vault "se ejecuta" solo si es válida y no falló
    logic exec;
    assign exec = !fault;

    // -------------------------------------------------------------------------
    // Ruta de lectura: ÚNICA salida de datos de la bóveda
    // -------------------------------------------------------------------------
    assign grant  = is_f4 && exec;
    assign subkey = grant ? vault_mem[f_kv][f_ronda] : 32'd0;

    // -------------------------------------------------------------------------
    // Salidas de estado
    // -------------------------------------------------------------------------
    assign auth     = auth_q;
    assign authfail = authfail_q;
    genvar g;
    generate
        for (g = 0; g < 4; g++) begin : g_kvalid
            assign kvalid[g] = &wmask[g];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Actualización de estado (un solo flanco)
    // -------------------------------------------------------------------------
    logic login_ok;
    assign login_ok = (challenge == password_reg);

    // Auto-logout: falla propia, falla en otro slot, o bundle fuera de región
    logic force_logout;
    assign force_logout = fault || fault_any || (valid && !in_secure);

    integer k, w;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (k = 0; k < 4; k++) begin
                wmask[k] <= 4'd0;
                for (w = 0; w < 4; w++) vault_mem[k][w] <= 32'd0;
            end
            challenge    <= 128'd0;
            password_reg <= ROT_SECRET_INIT;
            auth_q       <= 1'b0;
            authfail_q   <= 1'b0;
        end else begin
            // ---------------- Escrituras de datos -------------------------
            if (exec) begin
                if (is_ksetw) begin
                    vault_mem[fA][fB] <= rs_data;
                    wmask[fA][fB]     <= 1'b1;
                end
                if (is_authw) begin
                    challenge[32*fB +: 32] <= rs_data;
                end
                if (is_login || is_logout) begin
                    challenge <= 128'd0;               // D3
                end
                if (is_pwset) begin
                    password_reg <= challenge;         // D6
                    challenge    <= 128'd0;
                end
                if (is_kclr) begin
                    wmask[fB] <= 4'd0;
                    for (w = 0; w < 4; w++) vault_mem[fB][w] <= 32'd0;
                end
            end

            // ---------------- AUTH / AUTHFAIL -----------------------------
            if (exec && is_login) begin
                auth_q     <= login_ok && !force_logout;   // D4, D8
                authfail_q <= !login_ok;
            end else if (exec && is_logout) begin
                auth_q     <= 1'b0;
            end else if (force_logout) begin
                auth_q     <= 1'b0;
            end
        end
    end

endmodule
