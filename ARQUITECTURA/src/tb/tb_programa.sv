`timescale 1ns/1ps

// =============================================================================
// tb_programa.sv - Corre un programa cualquiera sobre el procesador completo.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Los demas testbenches de integracion traen su programa fijo y comprueban
// resultados conocidos. Este no: carga el binario que se le indique, lo deja
// correr hasta HALT y muestra el estado final, para probar programas nuevos
// escritos con la ISA sin tener que escribir un testbench para cada uno.
//
// Se usa a traves del makefile, que primero ensambla el programa:
//
//     make correr PROG=fibonacci.s
//     make correr PROG=... MOSTRAR=0x100 PALABRAS=48
//
// La memoria de datos arranca con lo que el programa declara en .data, o con
// otra imagen si se da MEMORIA=. Con VOLCADO= la memoria de datos completa se
// guarda en un archivo al terminar. Con esas dos cosas, cifrar un archivo es
// cargar, correr y extraer:
//
//     python3 ../../tools/load_file.py --input foto.png --output entrada.hex
//     make correr PROG=cifrar_archivo.s \
//                 MEMORIA=entrada.hex VOLCADO=salida.hex
//     python3 ../../tools/extract_data.py salida.hex -o cifrado.bin --cifrado
//
// -----------------------------------------------------------------------------
// ES UN EJECUTOR, NO UN TESTBENCH
// -----------------------------------------------------------------------------
// Conviene tenerlo claro antes de leer su salida: esto muestra lo que el
// procesador dejo, y no lo compara con nada. No tiene valores esperados, no
// cuenta casos y su unica condicion de fracaso es que el programa no llegue a
// HALT. Un programa que calcula mal termina igual de bien y se ve igual.
//
// Por eso no imprime "RESULTADO: OK" al final, aunque todos los demas
// testbenches del proyecto lo hagan: ahi esa linea significa que pasaron todos
// los casos, y aqui no hay ninguno. Dice "TERMINO" y lo aclara.
//
// Para que un programa quede verificado va a tb_ejemplos.sv, que lo corre y
// compara lo que deja contra valores calculados fuera del simulador. Este de
// aqui es para mirar: entender una latencia, ver donde se abre y se cierra la
// sesion de la boveda, o sacar la traza del pipeline para el documento.
//
// -----------------------------------------------------------------------------
// QUE MUESTRA
// -----------------------------------------------------------------------------
//   - Mientras corre: cada vez que cambia el bit AUTH del PSW (con el bundle
//     que lo provoco) y la primera falla.
//   - Al terminar: ciclos, bundles ejecutados, los 16 registros, el PSW
//     decodificado y, si se pidio, un tramo de la memoria de datos.
//   - Si se pidio, guarda la memoria de datos completa en un archivo.
//   - Con +TRAZA, el detalle de una ventana de ciclos, en dos partes:
//       diagrama del pipeline   una fila por bundle y una columna por ciclo,
//                               con la etapa en que esta: IF ID EX ME WB
//       eventos                 lo que paso ciclo por ciclo: registros y
//                               memoria escritos, saltos, banderas, boveda y
//                               fallas
//
// -----------------------------------------------------------------------------
// PLUSARGS
// -----------------------------------------------------------------------------
//   +PROGRAMA=archivo.hex   memoria de instrucciones (obligatorio)
//   +DATOS=archivo.hex      memoria de datos inicial (opcional)
//   +VOLCADO=archivo.hex    donde guardar la memoria de datos al terminar
//                           (opcional), en el formato de $writememh
//   +RESULTADO=archivo.txt  donde guardar el resumen final: ciclos, registros,
//                           PSW y la memoria pedida con MOSTRAR (opcional)
//   +FUENTE=programa.s      nombre del programa, para el encabezado de ese
//                           archivo (opcional)
//   +ESCRITURAS=archivo.txt cada escritura a registros y a memoria de toda
//                           la corrida, con su ciclo y su bundle (opcional)
//   +ESCRITURAS_MAX=n       tope de lineas de ese archivo (50 000)
//   +CICLOS=n               tope de ciclos antes de declarar que no termino
//   +MOSTRAR=n              direccion de byte desde donde mostrar la memoria
//   +PALABRAS=n             cuantas palabras de 32 bits mostrar
//   +TRAZA=n                detalle de los ciclos 1 a n
//   +TRAZA=a-b              detalle de los ciclos a a b
//   +TEXTO=archivo.txt      el texto de cada bundle, de listado_a_texto.py,
//                           para que la traza muestre instrucciones
//
// El unico resultado que este testbench juzga es si el programa llego a HALT.
// Que los valores sean los correctos lo decide quien escribio el programa.
// =============================================================================

`include "cerbero_defs.svh"

module tb_programa;

  localparam int CANTIDAD_BUNDLES  = 2048;
  localparam int CANTIDAD_PALABRAS = 16384;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic                         rst_n;
  logic                         detenido;
  logic [`XLEN-1:0]             psw;
  logic [`NREGS-1:0][`XLEN-1:0] registros;

  top #(
      .NUM_BUNDLES (CANTIDAD_BUNDLES),
      .NUM_WORDS   (CANTIDAD_PALABRAS),
      .RESET_PC    (32'h0000_0000)
  ) dut (
      .clk      (clk),
      .rst_n    (rst_n),
      .halted   (detenido),
      .psw      (psw),
      .dbg_regs (registros)
  );

  // ---------------------------------------------------------------------------
  // Nombre de cada causa de falla
  // ---------------------------------------------------------------------------

  function automatic string nombre_causa(input logic [2:0] causa);
    case (causa)
      `CAUSE_NONE:     return "ninguna";
      `CAUSE_ILLOP:    return "ILLOP (instruccion invalida)";
      `CAUSE_MISALIGN: return "MISALIGN (acceso desalineado)";
      `CAUSE_RANGE:    return "RANGE (direccion inexistente)";
      `CAUSE_DENIED:   return "DENIED (boveda sin permiso)";
      `CAUSE_NOKEY:    return "NOKEY (llave sin cargar)";
      `CAUSE_WCONF:    return "WCONF (dos slots al mismo registro)";
      default:         return "reservada";
    endcase
  endfunction

  // ---------------------------------------------------------------------------
  // Contadores
  //
  // El ciclo 1 es el primero despues de soltar el reset.
  // ---------------------------------------------------------------------------

  integer ciclo              = 0;
  integer bundles_ejecutados = 0;

  always @(posedge clk) begin
    if (rst_n) begin
      ciclo = ciclo + 1;
      if (dut.ex_valid) bundles_ejecutados = bundles_ejecutados + 1;
    end
  end

  // ---------------------------------------------------------------------------
  // Texto de cada bundle
  //
  // Indexado por numero de bundle (direccion / 16). Lo carga
  // cargar_texto_de_bundles desde el archivo de +TEXTO=, que genera
  // listado_a_texto.py a partir del listado del ensamblador.
  // ---------------------------------------------------------------------------

  string texto_de_bundle [0:CANTIDAD_BUNDLES-1];

  task automatic cargar_texto_de_bundles(input string archivo);
    integer       descriptor, leidos, indice;
    logic [31:0]  direccion;
    reg [8*240:1] linea_cruda;   // $fgets exige un reg, no un string
    string        linea;
    begin
      for (indice = 0; indice < CANTIDAD_BUNDLES; indice = indice + 1)
        texto_de_bundle[indice] = "";
      if (archivo == "") descriptor = 0;
      else               descriptor = $fopen(archivo, "r");
      if (descriptor == 0 && archivo != "") begin
        $display("    (no se pudo abrir %s: la traza muestra solo direcciones)",
                 archivo);
      end else if (descriptor != 0) begin
        while (!$feof(descriptor)) begin
          linea_cruda = 0;
          leidos = $fgets(linea_cruda, descriptor);
          linea  = string'(linea_cruda);
          // Cada linea es "DDDDDDDD texto": 8 digitos, un espacio, el texto
          if (leidos > 9 && $sscanf(linea, "%h", direccion) == 1 &&
              (direccion >> 4) < CANTIDAD_BUNDLES)
            texto_de_bundle[direccion >> 4] = linea.substr(9, linea.len() - 2);
        end
        $fclose(descriptor);
      end
    end
  endtask

  function automatic string texto_del_bundle_en(input logic [`XLEN-1:0] pc);
    if ((pc >> 4) < CANTIDAD_BUNDLES) return texto_de_bundle[pc >> 4];
    return "";
  endfunction

  // Para los eventos: el texto del bundle, o una descripcion si esta vacio
  function automatic string describir_bundle_en(input logic [`XLEN-1:0] pc);
    string texto;
    texto = texto_del_bundle_en(pc);
    if (texto == "-") return "sin operaciones";
    return texto;
  endfunction

  // Recorta o rellena con espacios hasta un ancho fijo, para alinear columnas.
  // Icarus no acepta el operador ?: entre strings, de ahi los if.
  function automatic string a_ancho(input string texto, input integer ancho);
    string resultado;
    resultado = texto;
    if (resultado.len() > ancho)
      resultado = {resultado.substr(0, ancho - 3), ".."};
    while (resultado.len() < ancho) resultado = {resultado, " "};
    return resultado;
  endfunction

  // ---------------------------------------------------------------------------
  // Traza: lo que se registra durante la ventana
  //
  // Todo se observa un instante despues del flanco de bajada. Para entonces
  // las senales del ciclo ya estan estables, incluida la lectura del banco de
  // registros, que ocurre justo en ese flanco; y todavia no llego la escritura
  // del flanco de subida siguiente.
  //
  // El pipeline nunca se detiene, asi que un bundle que esta en ID en el ciclo
  // c estuvo en IF en c-1 y va a estar en EX en c+1, en ME en c+2 y en WB en
  // c+3. Por eso alcanza con registrar que bundle hay en ID en cada ciclo para
  // dibujar el diagrama completo.
  // ---------------------------------------------------------------------------

  localparam int MAXIMO_CICLOS_DE_TRAZA = 500;
  localparam int MAXIMO_EVENTOS         = 4000;
  localparam int ANCHO_DE_ETIQUETA      = 34;   // direccion + instrucciones
  localparam int CICLOS_POR_BLOQUE      = 20;   // columnas del diagrama

  integer traza_desde = 0;
  integer traza_hasta = 0;      // 0: sin traza
  logic   traza_impresa = 1'b0;

  // Lo que hay en ID en cada ciclo, desde traza_desde-3 hasta traza_hasta+1.
  // El indice es ciclo - (traza_desde - 3).
  logic             id_hay_bundle [0:MAXIMO_CICLOS_DE_TRAZA+8];
  logic [`XLEN-1:0] id_direccion  [0:MAXIMO_CICLOS_DE_TRAZA+8];
  logic             id_salta      [0:MAXIMO_CICLOS_DE_TRAZA+8];
  logic [`XLEN-1:0] id_destino    [0:MAXIMO_CICLOS_DE_TRAZA+8];
  logic             id_detiene    [0:MAXIMO_CICLOS_DE_TRAZA+8];
  logic             id_es_salto   [0:MAXIMO_CICLOS_DE_TRAZA+8];   // tomado o no

  integer cantidad_de_eventos = 0;
  integer evento_ciclo [0:MAXIMO_EVENTOS-1];
  string  evento_texto [0:MAXIMO_EVENTOS-1];

  function automatic logic en_ventana(input integer c);
    return traza_hasta > 0 && c >= traza_desde && c <= traza_hasta;
  endfunction

  task automatic agregar_evento(input integer c, input string texto);
    begin
      if (en_ventana(c) && cantidad_de_eventos < MAXIMO_EVENTOS) begin
        evento_ciclo[cantidad_de_eventos] = c;
        evento_texto[cantidad_de_eventos] = texto;
        cantidad_de_eventos = cantidad_de_eventos + 1;
      end
    end
  endtask

  // Un slot S4 con BR, JAL, JR o JALR: un salto, se tome o no
  function automatic logic es_salto(input logic [15:0] slot_s4);
    logic [2:0] opcode;
    opcode = slot_s4[`S4_OPC];
    return opcode == `BRU_BR || opcode == `BRU_JAL ||
           opcode == `BRU_JR || opcode == `BRU_JALR;
  endfunction

  // ---------------------------------------------------------------------------
  // Traza: impresion
  // ---------------------------------------------------------------------------

  // Una celda del diagrama: la etapa en que esta en el ciclo c el bundle que
  // estuvo en ID en el ciclo ciclo_en_id
  function automatic string etapa(input integer ciclo_en_id, input integer c);
    case (c - ciclo_en_id)
      -1: return "  IF";
       0: return "  ID";
       1: return "  EX";
       2: return "  ME";
       3: return "  WB";
      default: return "    ";
    endcase
  endfunction

  task automatic imprimir_traza(input integer ultimo_ciclo);
    integer hasta, inicio_bloque, fin_bloque, c, k, base, indice;
    integer ciclo_en_id;
    string  fila, nota;
    begin
      hasta = traza_hasta;
      if (ultimo_ciclo < hasta) hasta = ultimo_ciclo;
      base  = traza_desde - 3;

      $display("");
      $display("  ===== traza de los ciclos %0d a %0d =====", traza_desde, hasta);

      // ---- diagrama del pipeline, en bloques de CICLOS_POR_BLOQUE columnas
      for (inicio_bloque = traza_desde; inicio_bloque <= hasta;
           inicio_bloque = inicio_bloque + CICLOS_POR_BLOQUE) begin
        fin_bloque = inicio_bloque + CICLOS_POR_BLOQUE - 1;
        if (fin_bloque > hasta) fin_bloque = hasta;

        $display("");
        fila = a_ancho("  bundle", ANCHO_DE_ETIQUETA + 2);
        for (c = inicio_bloque; c <= fin_bloque; c = c + 1)
          fila = {fila, $sformatf("%4d", c)};
        $display("%s", fila);

        // Una fila por cada bundle que pasa por alguna etapa dentro del bloque
        for (ciclo_en_id = inicio_bloque - 3; ciclo_en_id <= fin_bloque + 1;
             ciclo_en_id = ciclo_en_id + 1) begin
          indice = ciclo_en_id - base;
          if (ciclo_en_id >= 1 && indice >= 0 &&
              indice <= MAXIMO_CICLOS_DE_TRAZA + 8 && id_hay_bundle[indice]) begin
            fila = {"  ", a_ancho($sformatf("%05h  %s", id_direccion[indice][19:0],
                                            texto_del_bundle_en(id_direccion[indice])),
                                  ANCHO_DE_ETIQUETA)};
            for (c = inicio_bloque; c <= fin_bloque; c = c + 1)
              fila = {fila, etapa(ciclo_en_id, c)};

            nota = "";
            if (id_salta[indice])
              nota = $sformatf("   <- salta a %05h", id_destino[indice][19:0] & 20'hFFFF0);
            else if (id_es_salto[indice])
              nota = "   <- no salta";
            else if (id_detiene[indice])
              nota = "   <- HALT";
            else if (indice >= 1 && id_hay_bundle[indice - 1] &&
                     (id_es_salto[indice - 1] || id_detiene[indice - 1]))
              nota = "   (delay slot)";
            $display("%s%s", fila, nota);
          end
        end
      end

      // ---- eventos, en orden de ciclo
      $display("");
      $display("  eventos");
      if (cantidad_de_eventos == 0)
        $display("    (ninguno en esta ventana)");
      for (c = traza_desde; c <= hasta; c = c + 1)
        for (k = 0; k < cantidad_de_eventos; k = k + 1)
          if (evento_ciclo[k] == c)
            $display("    ciclo %5d  %s", c, evento_texto[k]);
      $display("");
      $display("  ===== fin de la traza =====");
      $display("");
      traza_impresa = 1'b1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Seguimiento ciclo por ciclo
  // ---------------------------------------------------------------------------

  logic             auth_anterior     = 1'b0;
  logic             authfail_anterior = 1'b0;
  logic             exc_anterior      = 1'b0;
  logic [3:0]       banderas_anteriores = 4'b0000;
  logic [`XLEN-1:0] pc_ex_del_ciclo_anterior = '0;   // el bundle que hoy esta en ME
  logic             ex_tenia_bundle = 1'b0;

  integer puerto, indice_registro;
  string  escrituras, causa_de_cierre;

  // Registro de escrituras: cada escritura a un registro (en WB) y a la
  // memoria de datos, de toda la corrida, en un archivo aparte
  integer canal_escrituras  = 0;
  integer lineas_escritas   = 0;
  integer tope_de_lineas    = 50000;
  task automatic anotar_escritura(input integer c, input logic [`XLEN-1:0] pc,
                                  input string que);
    if (canal_escrituras != 0) begin
      // Sin el texto del programa (con HEX=), va el bundle en hexadecimal
      if (lineas_escritas < tope_de_lineas && texto_del_bundle_en(pc) != "")
        $fdisplay(canal_escrituras, "  %7d  %05h  %-58s  // %s",
                  c, pc[19:0], que, texto_del_bundle_en(pc));
      else if (lineas_escritas < tope_de_lineas)
        $fdisplay(canal_escrituras, "  %7d  %05h  %-58s  // bundle %032h",
                  c, pc[19:0], que, dut.u_imem.storage[pc[`XLEN-1:4]]);
      else if (lineas_escritas == tope_de_lineas)
        $fdisplay(canal_escrituras,
                  "  ... se llego al tope de %0d lineas; ESCRITURAS_MAX= lo cambia",
                  tope_de_lineas);
      lineas_escritas = lineas_escritas + 1;
    end
  endtask
  logic [3:0] banderas;

  always @(negedge clk) begin
    #1;
    if (rst_n && ciclo > 0) begin

      // ---- lo que hay en ID, para el diagrama ----------------------------------
      if (traza_hasta > 0) begin
        indice_registro = ciclo - (traza_desde - 3);
        if (indice_registro >= 0 && indice_registro <= MAXIMO_CICLOS_DE_TRAZA + 8) begin
          id_hay_bundle[indice_registro] = dut.id_valid;
          id_direccion[indice_registro]  = dut.id_pc;
          id_salta[indice_registro]      = dut.id_valid && dut.id_taken;
          id_destino[indice_registro]    = dut.id_target;
          id_detiene[indice_registro]    = dut.id_valid && dut.id_halt;
          id_es_salto[indice_registro]   = dut.id_valid && es_salto(dut.id_s4);
        end
      end

      // ---- saltos y HALT, que se deciden en ID ---------------------------------
      if (dut.id_valid && dut.id_taken)
        agregar_evento(ciclo, $sformatf(
            "SALTO   %s en %05h salta a %05h; el delay slot %05h se ejecuta igual",
            texto_del_bundle_en(dut.id_pc), dut.id_pc[19:0],
            dut.id_target[19:0] & 20'hFFFF0, dut.id_pc[19:0] + 20'h10));
      if (dut.id_valid && !dut.id_taken && es_salto(dut.id_s4))
        agregar_evento(ciclo, $sformatf(
            "SALTO   %s en %05h no salta (condicion falsa); el delay slot %05h se ejecuta igual",
            texto_del_bundle_en(dut.id_pc), dut.id_pc[19:0], dut.id_pc[19:0] + 20'h10));
      if (dut.id_valid && dut.id_halt)
        agregar_evento(ciclo, $sformatf(
            "HALT    en %05h; se ejecuta su delay slot y el procesador se detiene",
            dut.id_pc[19:0]));

      // ---- escritura a memoria, desde EX ---------------------------------------
      if (dut.lsu_mem_we) begin
        if (dut.lsu_be == 4'b1111)
          anotar_escritura(ciclo, dut.ex_pc, $sformatf("MEM  [%05h] <- %08h",
                           dut.lsu_eff_addr[19:0], dut.lsu_wdata));
        else
          anotar_escritura(ciclo, dut.ex_pc, $sformatf("MEM  [%05h] <- %08h  bytes %b",
                           dut.lsu_eff_addr[19:0], dut.lsu_wdata, dut.lsu_be));
        if (dut.lsu_be == 4'b1111)
          agregar_evento(ciclo, $sformatf("MEM     [%05h] <- %08h   (bundle %05h)",
              dut.lsu_eff_addr[19:0], dut.lsu_wdata, dut.ex_pc[19:0]));
        else
          agregar_evento(ciclo, $sformatf("MEM     [%05h] <- %08h   (bundle %05h, bytes %b)",
              dut.lsu_eff_addr[19:0], dut.lsu_wdata, dut.ex_pc[19:0], dut.lsu_be));
      end

      // ---- escrituras a registros: ocurren en el flanco que abre WB, asi que
      //      se anotan en el ciclo siguiente, que es el WB del diagrama
      escrituras = "";
      for (puerto = 0; puerto < `NWRITE_PORTS; puerto = puerto + 1)
        if (dut.wb_wen[puerto])
          escrituras = {escrituras, $sformatf("r%0d <- %08h   ",
                        dut.wb_widx[puerto], dut.wb_wval[puerto])};
      if (escrituras != "" && ex_tenia_bundle)
        anotar_escritura(ciclo + 1, pc_ex_del_ciclo_anterior, {"REG  ", escrituras});
      if (escrituras != "" && ex_tenia_bundle)
        agregar_evento(ciclo + 1, $sformatf("REG     %s(bundle %05h)",
                       escrituras, pc_ex_del_ciclo_anterior[19:0]));

      // ---- banderas --------------------------------------------------------------
      banderas = {psw[`PSW_Z], psw[`PSW_N], psw[`PSW_C], psw[`PSW_V]};
      if (banderas !== banderas_anteriores) begin
        agregar_evento(ciclo, $sformatf("FLAGS   ZNCV %b -> %b",
                       banderas_anteriores, banderas));
        banderas_anteriores = banderas;
      end

      // ---- boveda: AUTH cambia en el flanco que cierra EX del bundle que lo
      //      provoca, asi que ese bundle es el que estaba en EX el ciclo anterior
      if (psw[`PSW_AUTH] !== auth_anterior) begin
        causa_de_cierre = "";
        if (!psw[`PSW_AUTH] &&
            (pc_ex_del_ciclo_anterior < `SEC_BASE_DEF ||
             pc_ex_del_ciclo_anterior > `SEC_LIMIT_DEF))
          causa_de_cierre = ": el PC salio de la region segura";
        agregar_evento(ciclo, $sformatf("BOVEDA  AUTH %0d -> %0d, por el bundle %05h (%s)%s",
            auth_anterior, psw[`PSW_AUTH], pc_ex_del_ciclo_anterior[19:0],
            describir_bundle_en(pc_ex_del_ciclo_anterior), causa_de_cierre));
        if (!en_ventana(ciclo))
          $display("  >> ciclo %0d: AUTH %0d -> %0d, por el bundle en 0x%08h%s",
                   ciclo, auth_anterior, psw[`PSW_AUTH], pc_ex_del_ciclo_anterior,
                   causa_de_cierre);
        auth_anterior = psw[`PSW_AUTH];
      end

      if (psw[`PSW_AUTHFAIL] !== authfail_anterior) begin
        if (psw[`PSW_AUTHFAIL])
          agregar_evento(ciclo, "BOVEDA  AUTHFAIL 0 -> 1: la contrasena no coincidio");
        else
          agregar_evento(ciclo, "BOVEDA  AUTHFAIL 1 -> 0");
        authfail_anterior = psw[`PSW_AUTHFAIL];
      end

      // ---- primera falla ---------------------------------------------------------
      if (psw[`PSW_EXC] && !exc_anterior) begin
        agregar_evento(ciclo, {"FALLA   ", nombre_causa(psw[`PSW_CAUSE])});
        if (!en_ventana(ciclo))
          $display("  >> ciclo %0d: primera falla, %s",
                   ciclo, nombre_causa(psw[`PSW_CAUSE]));
        exc_anterior = 1'b1;
      end

      pc_ex_del_ciclo_anterior = dut.ex_pc;
      ex_tenia_bundle          = dut.ex_valid;

      // ---- fin de la ventana -------------------------------------------------------
      if (traza_hasta > 0 && ciclo == traza_hasta && !traza_impresa)
        imprimir_traza(ciclo);
    end
  end

  // ---------------------------------------------------------------------------
  // Secuencia
  // ---------------------------------------------------------------------------

  string  archivo_programa, archivo_datos, archivo_volcado, archivo_texto;
  string  archivo_resultado, archivo_fuente, archivo_escrituras;

  // Copia de la memoria de datos al arrancar, para saber al final que palabras
  // cambio el programa
  localparam int MAXIMO_CAMBIOS_EN_PANTALLA = 64;
  logic [`XLEN-1:0] memoria_inicial [0:CANTIDAD_PALABRAS-1];
  integer cambios, primer_cambio, ultimo_cambio, mostrados;
  integer salida, canal_archivo = 0;
  string  pedido_de_traza;

  // +TRAZA=n es la ventana 1 a n; +TRAZA=a-b, la ventana a a b
  task automatic leer_ventana_de_traza(input string pedido);
    integer primero, segundo, leidos;
    begin
      leidos = $sscanf(pedido, "%d-%d", primero, segundo);
      if (leidos == 2) begin traza_desde = primero; traza_hasta = segundo; end
      else if (leidos == 1 && primero > 0) begin traza_desde = 1; traza_hasta = primero; end
      else begin traza_desde = 0; traza_hasta = 0; end
      if (traza_hasta > 0) begin
        if (traza_desde < 1) traza_desde = 1;
        if (traza_hasta - traza_desde + 1 > MAXIMO_CICLOS_DE_TRAZA) begin
          traza_hasta = traza_desde + MAXIMO_CICLOS_DE_TRAZA - 1;
          $display("    (la traza se limita a %0d ciclos: %0d a %0d)",
                   MAXIMO_CICLOS_DE_TRAZA, traza_desde, traza_hasta);
        end
      end
    end
  endtask
  integer tope_ciclos, mostrar_desde, palabras_a_mostrar;
  integer i;

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_programa.vcd");
      $dumpvars(0, tb_programa);
    end

    if (!$value$plusargs("PROGRAMA=%s", archivo_programa)) begin
      $display("falta +PROGRAMA=archivo.hex");
      $fatal(1, "sin programa");
    end
    if (!$value$plusargs("DATOS=%s", archivo_datos)) archivo_datos = "";
    if (!$value$plusargs("VOLCADO=%s", archivo_volcado)) archivo_volcado = "";
    if (!$value$plusargs("RESULTADO=%s", archivo_resultado)) archivo_resultado = "";
    if (!$value$plusargs("FUENTE=%s", archivo_fuente)) archivo_fuente = "";
    if (!$value$plusargs("ESCRITURAS=%s", archivo_escrituras)) archivo_escrituras = "";
    if (!$value$plusargs("ESCRITURAS_MAX=%d", tope_de_lineas)) tope_de_lineas = 50000;
    if (archivo_escrituras != "") begin
      canal_escrituras = $fopen(archivo_escrituras, "w");
      if (canal_escrituras == 0)
        $display("    (no se pudo abrir %s)", archivo_escrituras);
      else begin
        if (archivo_fuente != "")
          $fdisplay(canal_escrituras, "=== escrituras de %s ===", archivo_fuente);
        else
          $fdisplay(canal_escrituras, "=== escrituras de %s ===", archivo_programa);
        $fdisplay(canal_escrituras, "");
        $fdisplay(canal_escrituras,
                  "  REG: lo que el banco de registros guardo en WB.");
        $fdisplay(canal_escrituras,
                  "  MEM: lo que la LSU escribio en la memoria de datos.");
        $fdisplay(canal_escrituras,
                  "  El bundle es el que hizo la escritura; al final de la linea va su texto.");
        $fdisplay(canal_escrituras, "");
        $fdisplay(canal_escrituras, "    ciclo  bundle escritura");
      end
    end
    if (!$value$plusargs("CICLOS=%d", tope_ciclos))  tope_ciclos = 2000000;
    if (!$value$plusargs("MOSTRAR=%d", mostrar_desde)) mostrar_desde = 0;
    if (!$value$plusargs("PALABRAS=%d", palabras_a_mostrar)) palabras_a_mostrar = 0;
    if (!$value$plusargs("TRAZA=%s", pedido_de_traza)) pedido_de_traza = "0";
    leer_ventana_de_traza(pedido_de_traza);
    if (!$value$plusargs("TEXTO=%s", archivo_texto)) archivo_texto = "";
    cargar_texto_de_bundles(archivo_texto);

    rst_n = 1'b0;

    // Los bloques initial de imem y dmem barren sus arreglos a cero en el
    // tiempo 0, asi que la carga va un paso despues para no competir con ellos.
    #1;
    $readmemh(archivo_programa, dut.u_imem.storage);
    if (archivo_datos != "") $readmemh(archivo_datos, dut.u_dmem.storage);
    for (i = 0; i < CANTIDAD_PALABRAS; i = i + 1)
      memoria_inicial[i] = dut.u_dmem.storage[i];

    $display("=== tb_programa: %s ===", archivo_programa);
    if (archivo_datos != "")
      $display("    memoria de datos inicial: %s", archivo_datos);
    $display("");

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;

    while (!detenido && ciclo < tope_ciclos) @(posedge clk);
    // Que terminen los bundles que ya estaban dentro del pipeline
    repeat (8) @(posedge clk);
    #1;

    if (traza_hasta > 0 && !traza_impresa && ciclo >= traza_desde)
      imprimir_traza(ciclo);

    // ------------------------------------------------------------------------
    // El resumen final va a la pantalla y, con +RESULTADO=, tambien a un
    // archivo. Un descriptor multicanal escribe en los dos a la vez: el canal
    // 1 es la salida estandar y $fopen sin modo devuelve otro canal.
    salida = 1;
    if (archivo_resultado != "") begin
      canal_archivo = $fopen(archivo_resultado);
      if (canal_archivo == 0)
        $display("    (no se pudo abrir %s)", archivo_resultado);
      else begin
        salida = salida | canal_archivo;
        // Icarus 12 no acepta ?: entre cadenas, de ahi el if
        if (archivo_fuente != "")
          $fdisplay(canal_archivo, "=== resultado de %s ===", archivo_fuente);
        else
          $fdisplay(canal_archivo, "=== resultado de %s ===", archivo_programa);
      end
    end

    // ------------------------------------------------------------------------
    $fdisplay(salida, "");
    if (detenido)
      $fdisplay(salida, "  el programa llego a HALT en %0d ciclos, %0d bundles ejecutados",
               ciclo, bundles_ejecutados);
    else
      $fdisplay(salida, "  el programa NO llego a HALT en %0d ciclos", tope_ciclos);

    // ------------------------------------------------------------------------
    $fdisplay(salida, "");
    $fdisplay(salida, "  registros");
    for (i = 0; i < `NREGS; i = i + 2)
      $fdisplay(salida, "    r%-2d = %08h  %11d        r%-2d = %08h  %11d",
               i,     registros[i],     $signed(registros[i]),
               i + 1, registros[i + 1], $signed(registros[i + 1]));

    // ------------------------------------------------------------------------
    $fdisplay(salida, "");
    $fdisplay(salida, "  PSW = %08h", psw);
    $fdisplay(salida, "    banderas  Z=%0d N=%0d C=%0d V=%0d",
             psw[`PSW_Z], psw[`PSW_N], psw[`PSW_C], psw[`PSW_V]);
    $fdisplay(salida, "    boveda    AUTH=%0d AUTHFAIL=%0d",
             psw[`PSW_AUTH], psw[`PSW_AUTHFAIL]);
    $fdisplay(salida, "    fallas    EXC=%0d CAUSE=%s",
             psw[`PSW_EXC], nombre_causa(psw[`PSW_CAUSE]));

    // ------------------------------------------------------------------------
    if (palabras_a_mostrar > 0) begin
      $fdisplay(salida, "");
      $fdisplay(salida, "  memoria de datos desde 0x%08h", mostrar_desde);
      for (i = 0; i < palabras_a_mostrar; i = i + 1)
        $fdisplay(salida, "    0x%08h  %08h  %11d", mostrar_desde + 4 * i,
                 dut.u_dmem.storage[mostrar_desde / 4 + i],
                 $signed(dut.u_dmem.storage[mostrar_desde / 4 + i]));
    end

    // ------------------------------------------------------------------------
    // Lo que el programa escribio: las palabras de la memoria de datos que
    // terminan distintas de como empezaron. Una escritura que deja el mismo
    // valor que habia no aparece.
    cambios = 0; primer_cambio = -1; ultimo_cambio = -1; mostrados = 0;
    for (i = 0; i < CANTIDAD_PALABRAS; i = i + 1)
      if (dut.u_dmem.storage[i] !== memoria_inicial[i]) begin
        cambios = cambios + 1;
        if (primer_cambio < 0) primer_cambio = i;
        ultimo_cambio = i;
      end
    $fdisplay(salida, "");
    if (cambios == 0)
      $fdisplay(salida, "  memoria escrita por el programa: ninguna palabra cambio");
    else begin
      $fdisplay(salida, "  memoria escrita por el programa: %0d palabras, de 0x%08h a 0x%08h",
                cambios, 4 * primer_cambio, 4 * ultimo_cambio);
      $fdisplay(salida, "    direccion   antes     ahora     ahora (decimal)");
      for (i = primer_cambio; i <= ultimo_cambio; i = i + 1)
        if (dut.u_dmem.storage[i] !== memoria_inicial[i] &&
            mostrados < MAXIMO_CAMBIOS_EN_PANTALLA) begin
          $fdisplay(salida, "    0x%08h  %08h  %08h  %11d", 4 * i,
                    memoria_inicial[i], dut.u_dmem.storage[i],
                    $signed(dut.u_dmem.storage[i]));
          mostrados = mostrados + 1;
        end
      if (cambios > mostrados)
        $fdisplay(salida, "    ... y %0d palabras mas (VOLCADO= guarda la memoria completa)",
                  cambios - mostrados);
    end

    // ------------------------------------------------------------------------
    if (archivo_volcado != "") begin
      $writememh(archivo_volcado, dut.u_dmem.storage);
      $fdisplay(salida, "");
      $fdisplay(salida, "  memoria de datos completa guardada en %s", archivo_volcado);
    end

    if (canal_escrituras != 0) begin
      $fdisplay(canal_escrituras, "");
      $fdisplay(canal_escrituras, "  %0d escrituras en total", lineas_escritas);
      $fclose(canal_escrituras);
      $display("");
      $display("  escrituras guardadas en %s", archivo_escrituras);
      canal_escrituras = 0;
    end
    if (canal_archivo != 0) begin
      $fclose(canal_archivo);
      $display("");
      $display("  resultado guardado en %s", archivo_resultado);
    end

    $display("");
    $display("---");
    if (!detenido) begin
      $display("RESULTADO: FALLA (no termino; probar con CICLOS= mas alto)");
      $fatal(1, "el programa no llego a HALT");
    end
    // Deliberadamente NO se imprime "RESULTADO: OK". En este proyecto esa linea
    // significa "todos los casos pasaron", y aqui no hay casos: este ejecutor
    // no compara ni un solo valor contra nada. Lo unico que comprobo es que el
    // programa llego a HALT, que es lo que dice la linea de abajo.
    //
    // La distincion no es pedanteria. Un programa que calcula mal termina
    // igual de bien, y su salida se ve identica a la de uno correcto: el que
    // mira la pantalla es el oraculo. Si esto dijera OK, una corrida a mano
    // pasaria por verificacion y un error aritmetico se daria por descartado
    // sin que nadie comparara nada.
    //
    // Para que un programa quede verificado de verdad va a tb_ejemplos.sv, que
    // compara lo que deja contra valores calculados fuera del simulador.
    $display("TERMINO: el programa llego a HALT");
    $display("");
    $display("  Esto NO es una verificacion: este ejecutor muestra el resultado,");
    $display("  no lo compara con nada. Los programas comprobados contra sus");
    $display("  valores esperados estan en tb_ejemplos.sv (make ejemplos).");
    $finish;
  end

endmodule