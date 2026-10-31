// =============================================================================
// sesion_sin_logout.s - La sesion de la boveda se cierra sola al salir de la
// region segura, sin ejecutar LOGOUT.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// El programa principal salta a una rutina en la region segura (0x7000), que
// se autentica en la boveda y vuelve SIN hacer LOGOUT. Tres fotos del PSW,
// tomadas con MFPSW, muestran que la sesion se cierra sola en cuanto el PC
// sale de la region, y que despues una ronda de cifrado se rechaza:
//
//     make correr PROG=sesion_sin_logout.s MOSTRAR=0x300 PALABRAS=3
//
//   memoria  registro  cuando                               PSW esperado
//   0x300    r9        dentro de la region, tras LOGIN      0x00000010  AUTH = 1
//   0x304    r10       de vuelta afuera, sin LOGOUT         0x00000000  AUTH = 0
//   0x308    r11       tras intentar F4E afuera             0x00000240  EXC = 1,
//                                                                       CAUSE = DENIED
//
// Ademas, el ejecutor imprime en que ciclo y con que PC sube y baja AUTH: tiene
// que subir dentro de 0x7000-0x7FFF y bajar con el primer bundle de afuera.
//
// -----------------------------------------------------------------------------
// REGISTROS
// -----------------------------------------------------------------------------
//   r1 a r4   la contrasena de la boveda (ROT_SECRET de top.sv)
//   r9 a r11  las tres fotos del PSW
//   r12       0x7000, direccion de la rutina segura
//   r13       0x300, donde se guardan las fotos
//   r15       direccion de retorno, la escribe JALR
// =============================================================================

        .text
        .org 0x0000

inicio:
// La contrasena: cuatro palabras de 32 bits, armadas con MOVI (mitad baja) y
// MOVH (mitad alta). El MOVH tiene que ir al menos 3 bundles despues del MOVI.
        movi r1, #0x3210  | movi r2, #0xBA98 ;                //  0
        movi r3, #0xCDEF  | movi r4, #0x4567 ;                //  1
        movi r12, #0x7000 | movi r13, #0x300 ;                //  2
        - ;                                                   //  3
        movh r1, #0x7654  | movh r2, #0xFEDC ;                //  4
        movh r3, #0x89AB  | movh r4, #0x0123 ;                //  5

// Llamada a la rutina segura. JALR guarda en r15 la direccion de retorno, que
// es la de este salto mas 32: el bundle que sigue al delay slot.
        - | - | - | - | jalr.al r12 ;                         //  6
        - ;                                                   //  7 delay slot

// Aqui vuelve la rutina, ya fuera de la region segura y sin haber hecho
// LOGOUT. La boveda cierra la sesion con el primer bundle de afuera; se dejan
// pasar tres bundles antes de leer el PSW.
        - ;
        - ;
        - ;
        mfpsw r10 ;                                           // foto 2: AUTH = 0

// Intentar una ronda de cifrado fuera de la region y sin sesion: la boveda la
// anula y registra DENIED
        - | - | - | f4e p3, k0, #0 ;
        - ;
        - ;
        mfpsw r11         | - | sw r10, #4(r13) ;             // foto 3: DENIED
        - ;
        - ;
        - | - | sw r11, #8(r13) ;

        - | - | - | - | halt ;
        - ;                                                   // delay slot del halt

// =============================================================================
// Rutina segura
// =============================================================================

        .org 0x7000
        .secure

rutina_segura:
        - | - | - | authw #0, r1 ;
        - | - | - | authw #1, r2 ;
        - | - | - | authw #2, r3 ;
        - | - | - | authw #3, r4 ;
        - | - | - | login ;
        - ;
        - ;
        mfpsw r9 ;                                            // foto 1: AUTH = 1
        - ;
        - ;
        - | - | sw r9, #0(r13) ;

// Volver sin LOGOUT
        - | - | - | - | jr.al r15 ;
        - ;                                                   // delay slot del jr

        .endsecure