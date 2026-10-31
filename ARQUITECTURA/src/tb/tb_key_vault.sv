// =============================================================================
// tb_key_vault.sv  -  Testbench autoverificable de key_vault.sv
// Ejecutar desde src/build:  make key_vault     Ondas: src/build/tb_key_vault.vcd
// El archivo .vcd se puede redirigir con el plusarg +VCD=<ruta>.
// =============================================================================
`timescale 1ns/1ps

module tb_key_vault;

    // ---------------- Parámetros de prueba ----------------------------------
    localparam logic [127:0] PWD     = 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210;
    localparam logic [127:0] PWD2    = 128'hDEAD_BEEF_CAFE_BABE_0BAD_F00D_1234_5678;
    localparam logic [31:0]  PC_SEC  = 32'h0000_7000;   // dentro de la región segura
    localparam logic [31:0]  PC_USR  = 32'h0000_0100;   // código de usuario

    localparam logic [2:0] C_NONE = 3'b000, C_ILLOP = 3'b001,
                           C_DENIED = 3'b100, C_NOKEY = 3'b101;

    // ---------------- DUT ----------------------------------------------------
    logic        clk = 0, rst_n = 0;
    logic        valid = 0, fault_any = 0;
    logic [15:0] slot = 16'h0;
    logic [31:0] rs_data = 0, pc = PC_SEC;
    logic [31:0] subkey;
    logic        grant, fault, auth, authfail;
    logic [2:0]  cause;
    logic [3:0]  kvalid;

    key_vault #(.ROT_SECRET_INIT(PWD)) dut (.*);

    always #5 clk = ~clk;

    // ---------------- Codificadores (isa.md 2.5) -----------------------------
    function automatic [15:0] enc_f4e(input [2:0] par, input [1:0] kv, input [1:0] r);
        enc_f4e = {3'b001, par, kv, r, 6'b0};
    endfunction
    function automatic [15:0] enc_f4d(input [2:0] par, input [1:0] kv, input [1:0] r);
        enc_f4d = {3'b010, par, kv, r, 6'b0};
    endfunction
    function automatic [15:0] enc_ksetw(input [1:0] kv, input [1:0] w);
        enc_ksetw = {3'b011, kv, w, 4'd0, 5'b0};     // rs no importa en el TB
    endfunction
    function automatic [15:0] enc_authw(input [1:0] w);
        enc_authw = {3'b100, 2'b00, w, 4'd0, 5'b0};
    endfunction
    localparam [15:0] LOGIN  = {3'b101, 2'b00, 11'd0};
    localparam [15:0] LOGOUT = {3'b101, 2'b01, 11'd0};
    localparam [15:0] PWSET  = {3'b101, 2'b10, 11'd0};
    function automatic [15:0] enc_kclr(input [1:0] kv);
        enc_kclr = {3'b101, 2'b11, kv, 9'd0};
    endfunction

    // Llaves de prueba: KEY[k][w] = {k, w, patrón}
    function automatic [31:0] key_word(input [1:0] k, input [1:0] w);
        key_word = {4'hA, 2'b00, k, 4'hC, 2'b00, w, 16'h5A00 + 16'(k*4 + w)};
    endfunction

    // ---------------- Infraestructura de verificación -----------------------
    int errors = 0, checks = 0;
    string test_name;
    string vcd_file;

    string test_id;      // "T7"
    string stim;         // descripción del último estímulo aplicado
    int    t_checks, t_errors;

    // Desensamblador mínimo del slot S3 (para la columna Estímulo)
    function automatic string dis(input [15:0] s);
        case (s[15:13])
            3'b000: dis = "nop";
            3'b001: dis = $sformatf("f4e p%0d,k%0d,#%0d", s[12:10], s[9:8], s[7:6]);
            3'b010: dis = $sformatf("f4d p%0d,k%0d,#%0d", s[12:10], s[9:8], s[7:6]);
            3'b011: dis = $sformatf("ksetw k%0d,#%0d", s[12:11], s[10:9]);
            3'b100: dis = $sformatf("authw #%0d", s[10:9]);
            3'b101: case (s[12:11])
                        2'b00: dis = "login";
                        2'b01: dis = "logout";
                        2'b10: dis = "pwset";
                        2'b11: dis = $sformatf("kclr k%0d", s[10:9]);
                    endcase
            default: dis = "?";
        endcase
        if ((s[15:13] == 3'b001 || s[15:13] == 3'b010) ? (s[5:0] != 0) :
            (s[15:13] == 3'b101) ? ((s[12:11] == 2'b11) ? (s[8:0] != 0) : (s[10:0] != 0)) :
            (s[15:13] == 3'b100) ? (s[4:0] != 0 || s[12:11] != 0) :
            (s[15:13] == 3'b011) ? (s[4:0] != 0) : 1'b0)
            dis = {dis, " (reservado!=0)"};
    endfunction

    function automatic string region(input [31:0] p);
        region = (p >= 32'h7000 && p <= 32'h7FFF) ? "seg" : "usr";
    endfunction

    // Fila de tabla: | Test | Verificación | Estímulo | Obtenido | Esperado | Estado |
    task automatic check(input string what, input logic [31:0] got, input logic [31:0] exp);
        string st, row;
        checks++; t_checks++;
        st = (got === exp) ? "PASS" : "FAIL";
        if (got !== exp) begin errors++; t_errors++; end
        row = $sformatf("| %-3s | %-34s | %-58s | 0x%08h | 0x%08h | %s |",
                        test_id, what, stim, got, exp, st);
        $display("%s", row);
    endtask

    // Valores combinacionales de la última op (antes del flanco)
    logic [31:0] r_subkey; logic r_grant, r_fault; logic [2:0] r_cause;

    // Ejecuta una op durante un ciclo: maneja en negedge, muestrea antes del
    // posedge y deja que el estado se actualice en el posedge.
    task automatic op(input [15:0] s, input [31:0] data = 0,
                      input [31:0] p = PC_SEC, input logic fa = 0);
        @(negedge clk);
        valid = 1; slot = s; rs_data = data; pc = p; fault_any = fa;
        stim = $sformatf("%s rs=0x%08h pc=%s%s", dis(s), data, region(p),
                         fa ? " +fault_any" : "");
        #1;
        r_subkey = subkey; r_grant = grant; r_fault = fault; r_cause = cause;
        @(posedge clk); #1;
        valid = 0; slot = 0; rs_data = 0; fault_any = 0; pc = PC_SEC;
    endtask

    task automatic present(input [127:0] cred);
        for (int w = 0; w < 4; w++) op(enc_authw(w[1:0]), cred[32*w +: 32]);
        stim = $sformatf("authw x4 cred=%032h", cred);
    endtask

    task automatic do_login(input [127:0] cred);
        present(cred);
        op(LOGIN);
        stim = $sformatf("authw x4 %032h + login", cred);
    endtask

    task automatic install_key(input [1:0] k);
        for (int w = 0; w < 4; w++) op(enc_ksetw(k, w[1:0]), key_word(k, w[1:0]));
        stim = $sformatf("ksetw k%0d,#0..#3 (palabras de prueba)", k);
    endtask

    task automatic end_test();
        if (test_id != "") begin
            $display("|     | %-34s | %-58s |            |            | %0d/%0d |",
                     "subtotal", test_name, t_checks - t_errors, t_checks);
        end
    endtask

    task automatic begin_test(input string n);
        int i;
        end_test();
        test_name = n;
        test_id = n;
        i = 0;
        while (i < n.len() && n[i] != " ") i++;     // Icarus no soporta break
        test_id   = n.substr(0, i-1);
        test_name = n.substr(i+1, n.len()-1);
        t_checks = 0; t_errors = 0;
        stim = "(estado actual)";
        $display("|-----|------------------------------------|------------------------------------------------------------|------------|------------|------|");
        $display("| %-3s | %s", test_id, test_name);
    endtask

    // ---------------- Monitor de aislamiento ---------------------------------
    // En TODO ciclo: si grant=0, subkey debe ser 0 (ninguna fuga por la salida).
    always @(negedge clk) if (rst_n && !grant && subkey !== 32'd0) begin
        errors++;
        $display("  [FAIL] Fuga: subkey=0x%08h con grant=0 en t=%0t", subkey, $time);
    end

    // ---------------- Secuencia de pruebas -----------------------------------
    initial begin
        if (!$value$plusargs("VCD=%s", vcd_file)) vcd_file = "tb_key_vault.vcd";
        $dumpfile(vcd_file);
        $dumpvars(0, tb_key_vault);
        $display("| Test| Verificación                       | Estímulo                                                   | Obtenido   | Esperado   | Estado |");

        repeat (2) @(posedge clk);
        rst_n = 1;

        // T1 ------------------------------------------------------------------
        begin_test("T1 Estado de reset");
        stim = "rst_n=0 por 2 ciclos";
        check("auth", auth, 0);
        check("authfail", authfail, 0);
        check("kvalid", kvalid, 0);

        // T2 ------------------------------------------------------------------
        begin_test("T2 LOGIN con credencial incorrecta");
        do_login(~PWD);
        check("fault (LOGIN fallido no es falla)", r_fault, 0);
        check("auth", auth, 0);
        check("authfail", authfail, 1);

        // T3 ------------------------------------------------------------------
        begin_test("T3 KSETW sin autenticar -> DENIED");
        op(enc_ksetw(0, 0), 32'h1111_1111);
        check("cause", r_cause, C_DENIED);
        check("kvalid", kvalid, 0);

        // T4 ------------------------------------------------------------------
        begin_test("T4 LOGIN correcto");
        do_login(PWD);
        check("auth", auth, 1);
        check("authfail limpiado", authfail, 0);

        // T5 ------------------------------------------------------------------
        begin_test("T5 F4E sobre ranura vacia -> NOKEY y cierre de sesion");
        op(enc_f4e(0, 0, 0));
        check("cause", r_cause, C_NOKEY);
        check("grant", r_grant, 0);
        check("auth tras falla", auth, 0);

        // T6 ------------------------------------------------------------------
        begin_test("T6 Instalar las 4 llaves (KVALID progresivo)");
        do_login(PWD);
        for (int w = 0; w < 3; w++) op(enc_ksetw(0, w[1:0]), key_word(0, w[1:0]));
        check("kvalid con 3/4 palabras", kvalid, 4'b0000);
        op(enc_ksetw(0, 3), key_word(0, 3));
        check("kvalid llave 0", kvalid, 4'b0001);
        install_key(1); install_key(2); install_key(3);
        check("kvalid todas", kvalid, 4'b1111);
        check("auth sigue abierta", auth, 1);

        // T7 ------------------------------------------------------------------
        begin_test("T7 Lectura de las 16 subllaves (F4E y F4D)");
        for (int k = 0; k < 4; k++)
            for (int r = 0; r < 4; r++) begin
                op((r % 2) ? enc_f4d(k[2:0], k[1:0], r[1:0]) : enc_f4e(k[2:0], k[1:0], r[1:0]));
                check($sformatf("grant k%0d r%0d", k, r), r_grant, 1);
                check($sformatf("subkey k%0d r%0d", k, r), r_subkey, key_word(k[1:0], r[1:0]));
                check($sformatf("fault k%0d r%0d", k, r), r_fault, 0);
            end

        // T8 ------------------------------------------------------------------
        begin_test("T8 Op privilegiada con AUTH=1 pero PC fuera de region -> DENIED");
        op(enc_f4e(0, 1, 0), 0, PC_USR);
        check("cause", r_cause, C_DENIED);
        check("subkey no expuesta", r_subkey, 0);
        check("auth cae", auth, 0);

        // T9 ------------------------------------------------------------------
        begin_test("T9 Auto-logout al salir de la region segura (sin op del vault)");
        do_login(PWD);
        check("auth abierta", auth, 1);
        op(16'h0000, 0, PC_USR);              // bundle de usuario con S3 = NOP
        check("auth tras salir", auth, 0);

        // T10 -----------------------------------------------------------------
        begin_test("T10 fault_any limpia AUTH; la op del vault del mismo bundle aplica");
        do_login(PWD);
        op(enc_ksetw(3, 0), 32'h3333_0000, PC_SEC, 1'b1);
        check("fault propio", r_fault, 0);
        check("auth", auth, 0);
        check("kvalid[3] se mantiene", kvalid[3], 1);
        do_login(PWD);
        op(enc_f4e(3, 3, 0));
        check("palabra reescrita", r_subkey, 32'h3333_0000);

        // T11 -----------------------------------------------------------------
        begin_test("T11 LOGIN exitoso + fault_any en el mismo bundle -> AUTH=0");
        op(LOGOUT);
        present(PWD);
        op(LOGIN, 0, PC_SEC, 1'b1);
        check("auth", auth, 0);
        check("authfail", authfail, 0);

        // T12 -----------------------------------------------------------------
        begin_test("T12 LOGIN fuera de la region segura no abre sesion");
        present(PWD);
        op(LOGIN, 0, PC_USR);
        check("auth", auth, 0);

        // T13 -----------------------------------------------------------------
        begin_test("T13 LOGIN limpia el desafio (no se puede repetir sin AUTHW)");
        do_login(PWD);
        check("auth", auth, 1);
        op(LOGOUT);
        check("auth tras LOGOUT", auth, 0);
        op(LOGIN);
        check("auth sin re-presentar", auth, 0);
        check("authfail", authfail, 1);

        // T14 -----------------------------------------------------------------
        begin_test("T14 LOGOUT no borra las llaves");
        check("kvalid", kvalid, 4'b1111);

        // T15 -----------------------------------------------------------------
        begin_test("T15 PWSET: la credencial vieja deja de servir");
        do_login(PWD);
        present(PWD2);
        op(PWSET);
        check("fault", r_fault, 0);
        op(LOGOUT);
        do_login(PWD);
        check("auth con pwd vieja", auth, 0);
        do_login(PWD2);
        check("auth con pwd nueva", auth, 1);

        // T16 -----------------------------------------------------------------
        begin_test("T16 KCLR borra la ranura -> F4E da NOKEY");
        op(enc_kclr(2));
        check("kvalid", kvalid, 4'b1011);
        op(enc_f4e(0, 2, 0));
        check("cause", r_cause, C_NOKEY);
        check("subkey", r_subkey, 0);

        // T17 -----------------------------------------------------------------
        begin_test("T17 PWSET y KCLR sin AUTH -> DENIED");
        check("auth (cerrada por NOKEY)", auth, 0);
        op(PWSET);
        check("PWSET cause", r_cause, C_DENIED);
        op(enc_kclr(0));
        check("KCLR cause", r_cause, C_DENIED);
        check("kvalid intacto", kvalid, 4'b1011);

        // T18 -----------------------------------------------------------------
        begin_test("T18 Bits reservados -> ILLOP, sin efecto");
        do_login(PWD2);
        op(enc_ksetw(2, 0) | 16'h0001, 32'hBAD0_BAD0);   // bit [0] reservado
        check("cause", r_cause, C_ILLOP);
        check("kvalid[2] sigue en 0", kvalid[2], 0);
        check("auth cae por falla", auth, 0);
        op(LOGIN | 16'h0200);                              // [10:9] != 0 en LOGIN
        check("LOGIN reservado cause", r_cause, C_ILLOP);
        op(enc_f4e(0, 0, 0) | 16'h0020);                   // [5] reservado en tipo F
        check("F4E reservado cause", r_cause, C_ILLOP);

        // T19 -----------------------------------------------------------------
        begin_test("T19 AUTHW no requiere AUTH; valid=0 no tiene efecto");
        check("auth", auth, 0);
        op(enc_authw(0), 32'h1234_5678);
        check("AUTHW fault", r_fault, 0);
        @(negedge clk); valid = 0; slot = enc_ksetw(0, 0); rs_data = 32'hFFFF_FFFF; #1;
        stim = "ksetw k0,#0 rs=0xffffffff con valid=0";
        check("sin valid no hay falla", fault, 0);
        @(posedge clk); #1; slot = 0;

`ifdef FORCE_FAIL
        // ---------------- Autoprueba del arnes --------------------------------
        // Un testbench que siempre pasa no prueba nada. Compilar con
        // -DFORCE_FAIL inyecta un caso deliberadamente incorrecto para
        // comprobar que el arnes sabe reportar una falla.
        stim = "caso deliberadamente incorrecto";
        check("autoprueba del arnes", 32'h0000_0000, 32'hFFFF_FFFF);
`endif

        // ---------------- Resumen --------------------------------------------
        end_test();
        $display("==================================================");
        if (errors == 0) $display(" PASS  key_vault: %0d verificaciones OK", checks);
        else             $display(" FAIL  key_vault: %0d errores de %0d verificaciones", errors, checks);
        $display("==================================================");
        // $fatal devuelve código de salida distinto de 0: `make` se detiene
        if (errors != 0) $fatal(1, "tb_key_vault: hubo errores");
        $finish;
    end

    // Watchdog
    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
