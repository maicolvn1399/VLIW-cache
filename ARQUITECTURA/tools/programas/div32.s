// =============================================================================
// div32.s - Subrutina de division entera sin signo de 32 bits.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// La seccion 11 del ISA dice que CERBERO no incluye instruccion de division y
// que esta se provee como subrutina, escrita en ensamblador propio y entregada
// junto con el ISA. Este es ese archivo.
//
// -----------------------------------------------------------------------------
// CONVENCION DE LLAMADA
// -----------------------------------------------------------------------------
//   entrada    R6 = dividendo, R7 = divisor
//   salida     R6 = cociente,  R7 = residuo
//   destruye   R1, R2, R3, R4, R5
//   preserva   R8 a R14, y R15 porque retorna con jr
//
// La lista de registros que destruye es parte del contrato: el generador de
// codigo de CE1108 tiene que guardar lo que le importe de R1 a R5 antes de
// llamar. No se guardan aqui a proposito: cada push y cada pop costarian un
// acceso a memoria y tres bundles de separacion, y el llamador casi siempre
// sabe que no le hacen falta.
//
// Se llama con JAL si cabe en el alcance relativo, o con MOVI mas JALR si no:
//
//     movi r12, #__div32 ;        // la etiqueta tambien sirve de inmediato
//     - ;  - ;  - ;
//     - | - | - | - | jalr.al r12 ;
//     - ;                         // delay slot
//
// -----------------------------------------------------------------------------
// DIVISION POR CERO
// -----------------------------------------------------------------------------
// No falla ni se cuelga: con el divisor en cero, la comparacion de cada paso
// siempre da "cabe", nunca se resta nada y el cociente acumula unos. El
// resultado es cociente = 0xFFFFFFFF y residuo = el dividendo, que es la misma
// convencion que define RISC-V para DIVU. Queda documentado porque un programa
// que divida por cero va a obtener eso y no una falla del PSW.
//
// -----------------------------------------------------------------------------
// POR QUE EL LAZO NO TIENE SALTOS ADENTRO
// -----------------------------------------------------------------------------
// El paso de un algoritmo de division por restas desplazadas es "si el residuo
// alcanza al divisor, restarlo y poner un uno en el cociente". Lo natural seria
// un salto condicional, pero aqui se hace sin ninguno:
//
//     cmp   r2, r7      // C = 1 si r2 < r7, porque C es PRESTAMO en este ISA
//     setcc r5, geu     // r5 = 1 si r2 >= r7, o sea si cabe
//     mul   r4, r5, r7  // r4 = r7 si cabe, 0 si no
//     sub   r2, r2, r4  // resta condicional, sin ramificar
//     or    r1, r1, r5  // y el bit del cociente
//
// Tres razones. La primera es que un lazo sin saltos internos se verifica
// mirandolo: no hay dos caminos que converjan ni un delay slot que haya que
// razonar dos veces. La segunda es que tarda lo mismo con cualquier entrada,
// que en una rutina que puede terminar manejando datos de una sesion de boveda
// no es un detalle menor. La tercera es que SETcc existe justo para esto: es
// una de las dos instrucciones que la v1.1 agrego al ISA.
//
// El truco del MUL merece una nota: r5 vale 0 o 1, asi que multiplicarlo por el
// divisor da el divisor o da cero. Es mas corto que construir una mascara con
// NEG y AND, que costaria tres bundles mas de cadena.
//
// -----------------------------------------------------------------------------
// COSTO
// -----------------------------------------------------------------------------
// El lazo son 21 bundles y da 32 vueltas, asi que una division cuesta unos 680
// ciclos. La mayor parte son bundles vacios: la cadena de dependencias tiene
// siete pasos y cada uno exige los tres bundles de separacion que fija el ISA.
//
// Se puede reducir casi a la mitad entrelazando dos vueltas del lazo para que
// los huecos de una se llenen con el trabajo de la otra. No se hizo porque esa
// transformacion es donde viven los errores de calendarizacion, y una rutina de
// biblioteca que el compilador va a emitir en todas partes conviene tenerla
// obviamente correcta antes que rapida. El ISA ya advierte que la division es
// multiciclo por naturaleza.
// =============================================================================

        .text

// -----------------------------------------------------------------------------
__div32:
// Cociente y residuo en cero, contador en 32
        movi r1, #0       | movi r2, #0 ;
        movi r3, #32 ;
        - ;
        - ;

__div32_lazo:
// Entra el bit mas alto del dividendo al residuo, y los dos acumuladores se
// corren una posicion. Los cuatro slots leen el estado previo al bundle, asi
// que `srli r4, r6` toma el R6 de antes de que `slli r6` lo corra.
        srli r4, r6, #31 | slli r2, r2, #1 ;
        slli r6, r6, #1  | slli r1, r1, #1 ;
        subi r3, r3, #1 ;
        or   r2, r2, r4 ;
        - ;
        - ;

// Cabe o no cabe. C es prestamo, asi que GEU es exactamente "r2 alcanza a r7".
        cmp  r2, r7 ;
        - ;
        - ;
        setcc r5, geu ;
        - ;
        - ;

// Resta condicional sin ramificar, y el bit del cociente
        mul  r4, r5, r7  | or r1, r1, r5 ;
        - ;
        - ;
        sub  r2, r2, r4 ;

// Fin del lazo
        cmpi r3, #0 ;
        - ;
        - ;
        - | - | - | - | br.ne __div32_lazo ;
        - ;                               // delay slot del salto del lazo

// -----------------------------------------------------------------------------
// Salida: el cociente a R6 y el residuo a R7
        mov  r6, r1      | mov r7, r2 ;
        - ;
        - ;
        - | - | - | - | jr.al r15 ;
        - ;                               // delay slot del retorno
