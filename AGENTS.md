# Contexto del proyecto
Compilador Nova -> procesador VLIW CERBERO (CE1108, Proyecto II). Entrega 20-nov-2026.
Especificacion: documentacion/ESPECIFICACION_PROYECTO2.txt (si hay conflicto, gana la especificacion).
Secciones relevantes: 4, 6, 7.2, 7.3, 8.2, 9.2. La seccion 3 (cache) es de otro equipo.

Pipeline: fase1_lexico -> fase2_sintactico -> fase3_semantico -> fase4_codigo (tac.c, codegen.c)
-> fase6_optimizacion (bloques.c CFG, vivacidad.c, muerto.c DCE). Banderas en main.c. IDE en
fase5_ide/ e ide/. Build: `make`. Pruebas: `make test`, `make prueba-ide`, `make prueba-rtl`.

Estado: -O1 solo hace DCE. codegen.c arma un grafo de dependencias por bloque,
calendariza por camino critico, empaqueta S0/S1 y llena slots de delay solo con
operaciones independientes seguras. `--calendario` muestra los slots y la causa
de cada NOP. Los temporales viven en pila; solo se usan R10/R11.

Contrato ISA (ARQUITECTURA/docs/isa.md):
- Bundle de 5 slots: S0 ALU-0 (unico que escribe banderas/CMP), S1 ALU-1, S2 LSU, S3 CRP, S4 BRU.
- Latencia de 3 bundles entre productor y consumidor (ALU, load, banderas, R15). Sin forwarding
  ni deteccion de riesgos: el compilador es responsable.
- Delay slot tras cada salto (siempre se ejecuta, sin otro salto en S4).
- Dos slots no escriben el mismo registro en un bundle.
- R0-R5 cripto (__div32 destruye R1-R5), R6-R9 args (R6 retorno), R10-R11 temporales,
  R12-R15 reservados.

Reglas:
- NO modificar ARQUITECTURA/ ni el ISA.
- Toda optimizacion preserva R6, la salida de `scribe` y los codigos de aborto 134/136/137.
  No eliminar divisiones, CHECK, STORE ni llamadas con efectos.
- Tras cada cambio deben pasar `make test`, `make prueba-ide` y `make prueba-rtl`.
- No silenciar advertencias para que pasen pruebas. Commits pequenos y descriptivos.
- Al terminar, resumir: archivos tocados, banderas nuevas, pruebas agregadas, limitaciones.