// =============================================================================
// vault_sesion.s - Abre la sesion de la boveda e instala la llave.
// CE-4301 Arquitectura de Computadores I - Proyecto Grupal I - Grupo #4
//
// Se INCLUYE, igual que cargar_llave.s: son bundles en linea recta, sin
// etiquetas y sin retorno.
//
// -----------------------------------------------------------------------------
// TIENE QUE QUEDAR DENTRO DE LA REGION SEGURA
// -----------------------------------------------------------------------------
// Esto no es una recomendacion, es lo que el hardware exige, y conviene tenerlo
// claro antes de mover una linea:
//
//   LOGIN  no es privilegiada, pero la boveda solo enciende AUTH si el bundle
//          que la ejecuta esta dentro de [SEC_BASE, SEC_LIMIT]. Un login fuera
//          de la region no falla: simplemente no abre sesion, porque la regla
//          de cierre automatico se aplica en el mismo flanco.
//   KSETW  es privilegiada: exige AUTH = 1 Y estar dentro de la region.
//   F4E    y F4D, lo mismo.
//
// En consecuencia TODO el camino, desde el LOGIN hasta la ultima ronda, vive en
// la region segura, y por eso los dos programas de archivo ponen su lazo ahi en
// vez de en el codigo de usuario. El unico trozo que puede quedar afuera es la
// carga de las constantes, que es lo que hace cargar_llave.s.
//
// -----------------------------------------------------------------------------
// ENTRADA
// -----------------------------------------------------------------------------
//   R1 a R4   las cuatro palabras de la credencial
//   R5 a R8   las cuatro palabras de la llave
//
// Al salir, AUTH esta encendido y KVALID[0] tambien, asi que las rondas sobre la
// ranura 0 ya tienen permiso. No se comprueba que el LOGIN haya salido bien: si
// la credencial fuera incorrecta, AUTH quedaria en cero y las rondas se
// anularian con DENIED, que es lo que el PSW va a reportar. Un programa de
// produccion pondria aqui un `br.auth` para separar los dos casos.
// =============================================================================

// Paso 1 del protocolo de isa.md 8.2: las cuatro palabras al registro de desafio
        - | - | - | authw #0, r1 ;
        - | - | - | authw #1, r2 ;
        - | - | - | authw #2, r3 ;
        - | - | - | authw #3, r4 ;

// Paso 2: autenticar
        - | - | - | login ;
        - ;
        - ;

// Paso 4: instalar la llave en la ranura 0. Requiere AUTH, que quedo listo tres
// bundles despues del LOGIN.
//
// En los mismos bundles, las dos ALU borran la contrasena (r1 a r4) y la llave
// (r5 a r8). Una vez en la boveda, ninguna de las dos tiene por que seguir en
// registros, donde cualquier codigo que corra despues podria leerlas.
//
// Borrar un registro en el mismo bundle en que KSETW lo lee es seguro: todos
// los slots de un bundle leen el estado de los registros PREVIO al bundle, asi
// que cada KSETW toma la palabra de la llave antes de que se borre. Por eso el
// borrado no agrega ningun bundle al programa.
        movi r1, #0 | movi r2, #0 | - | ksetw k0, #0, r5 ;
        movi r3, #0 | movi r4, #0 | - | ksetw k0, #1, r6 ;
        movi r5, #0 | movi r6, #0 | - | ksetw k0, #2, r7 ;
        movi r7, #0 | movi r8, #0 | - | ksetw k0, #3, r8 ;
        - ;
        - ;