// =============================================================================
// cifrar_archivo.s - Cifra un archivo completo, bloque por bloque.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Es el caso 6 del enunciado. Recorre el buffer que dejo load_file.py y cifra
// cada bloque de 64 bits con cuatro rondas Feistel4, en el sitio.
//
//   entrada    el buffer en 0x4000, con la cabecera que fija formato_buffer.py
//   salida     el mismo buffer, con los datos cifrados y la cabecera intacta
//
// La cabecera NO se cifra: el puntero arranca en 0x4008 y las dos palabras de
// 0x4000 y 0x4004 quedan como estaban. Es a proposito, y por dos motivos. Uno,
// extract_data.py necesita leer la cantidad de bytes para recortar el relleno.
// Dos, la longitud de un archivo no es secreta y cifrarla obligaria a guardarla
// en otra parte.
//
// -----------------------------------------------------------------------------
// ESTRUCTURA
// -----------------------------------------------------------------------------
// El programa principal vive en el codigo de usuario y todo el trabajo de
// boveda y cifrado en la region segura, porque F4E es privilegiada y exige AUTH
// mas estar dentro de [SEC_BASE, SEC_LIMIT]. La llamada va con JALR porque de
// 0x0000 a 0x7000 hay 1791 bundles y el salto relativo alcanza 512.
//
// Al retornar, el PC deja la region y la boveda cierra la sesion sola. El
// programa no ejecuta LOGOUT y no le hace falta.
//
// -----------------------------------------------------------------------------
// EL LAZO
// -----------------------------------------------------------------------------
// Veintiun bundles por bloque, de los cuales trece son vacios: entre ronda y
// ronda hay que dejar los tres bundles de separacion que exige el ISA, porque
// cada una lee el par que escribio la anterior. Los huecos que se podian llenar
// con trabajo independiente ya lo estan: el decremento de la cuenta y su
// comparacion viven dentro de la cadena de las rondas.
//
// El par es P5, o sea R10 y R11, con la mitad L en el registro par.
// =============================================================================

        .text
        .org 0x0000

inicio:
        .include "cargar_llave.s"

// Llamada a la rutina segura. El enlace apunta dos bundles adelante.
        - | - | - | - | jalr.al r12 ;
        - ;                                   // delay slot del jalr

// Aqui aterriza el retorno
        - | - | - | - | halt ;
        - ;                                   // delay slot del halt

// =============================================================================
// Rutina de cifrado, dentro de la region segura
// =============================================================================

        .org 0x7000
        .secure

cifrar:
        .include "vault_sesion.s"

// Si el archivo esta vacio no hay bloques que recorrer
        cmpi r9, #0 ;
        - ;
        - ;
        - | - | - | - | br.eq fin_cifrar ;
        - ;                                   // delay slot

lazo_cifrar:
// El bloque entra al par P5
        - | - | lw r10, #0(r13) ;
        - | - | lw r11, #4(r13) ;
        subi r9, r9, #1 ;                     // trabajo independiente en el hueco
        - ;

// Cuatro rondas, cada una separada tres bundles de la anterior
        - | - | - | f4e p5, k0, #0 ;
        cmpi r9, #0 ;                         // tambien aprovecha el hueco
        - ;
        - | - | - | f4e p5, k0, #1 ;
        - ;
        - ;
        - | - | - | f4e p5, k0, #2 ;
        - ;
        - ;
        - | - | - | f4e p5, k0, #3 ;
        - ;
        - ;

// El bloque cifrado vuelve a su sitio y el puntero avanza
        - | - | sw r10, #0(r13) ;
        - | - | sw r11, #4(r13) ;
        addi r13, r13, #8 ;
        - | - | - | - | br.ne lazo_cifrar ;
        - ;                                   // delay slot del lazo

fin_cifrar:
        - | - | - | - | jr.al r15 ;
        - ;                                   // delay slot del retorno

        .endsecure
