/*
 * Catalogo de diagnosticos.
 *
 * El compilador ya dice que esta mal y donde. Lo que falta para que un editor
 * sea util es la otra mitad: por que el lenguaje lo prohibe y cual es el
 * cambio concreto que lo arregla. Esa es la informacion que esta tabla agrega,
 * y es la que el IDE muestra en el globo del subrayado y en la lista de
 * problemas.
 *
 * La tabla se mantiene junto a los codigos reales que emiten las fases: si se
 * agrega un codigo nuevo al compilador y no se agrega aqui, 'make prueba-ide'
 * lo reporta como hueco del catalogo.
 */
#include <string.h>
#include "ide.h"

static const EntradaCatalogo catalogo[] = {

/* --- Fase 1: analisis lexico ------------------------------------------- */
{"E101", "Caracter no valido",
 "El caracter no forma parte del alfabeto de Nova fuera de una cadena de texto. "
 "Suele aparecer al pegar texto desde un procesador de palabras, que sustituye "
 "las comillas rectas por comillas tipograficas.",
 "Borre el caracter, o enciarrelo entre comillas dobles si queria que fuera "
 "texto."},

{"E102", "Cadena sin cerrar",
 "Una cadena abierta con comilla doble llego al fin de linea sin su comilla de "
 "cierre. En Nova las cadenas no cruzan lineas.",
 "Agregue la comilla doble de cierre antes del fin de linea."},

{"E103", "Comentario de bloque sin cerrar",
 "Un comentario abierto con '#{' llego al final del archivo sin su cierre, de "
 "modo que el resto del programa quedo comentado.",
 "Cierre el comentario con '}#'."},

{"E104", "Escape desconocido",
 "Dentro de una cadena solo se reconocen los escapes \\n, \\t, \\\\ y \\\".",
 "Use uno de los escapes validos, o duplique la barra invertida si queria una "
 "barra literal."},

{"E105", "Literal numerico mal formado",
 "Un numero quedo pegado a un identificador, o un prefijo hexadecimal '0x' se "
 "quedo sin digitos. El lexer no puede decidir donde termina el numero.",
 "Separe el numero del identificador con un espacio o un operador, y complete "
 "los digitos del literal hexadecimal."},

{"E106", "Literal fuera de rango",
 "El valor no cabe en un 'integer', que en Nova es de 32 bits con signo "
 "(-2147483648 a 2147483647).",
 "Use un valor dentro del rango, o reparta el calculo en varias operaciones."},

{"E107", "Identificador demasiado largo",
 "Nova limita los nombres a 255 caracteres para poder acotar las estructuras de "
 "la tabla de simbolos.",
 "Acorte el nombre a 255 caracteres o menos; un nombre tan largo casi siempre "
 "viene de texto pegado por accidente."},

/* --- Fase 2: analisis sintactico --------------------------------------- */
{"E201", "Token inesperado",
 "La secuencia de tokens no corresponde a ninguna produccion de la gramatica en "
 "este punto. Es el error tipico de un parentesis, una coma o una palabra "
 "reservada mal colocada.",
 "Revise el token senalado contra la forma esperada que indica el mensaje; el "
 "panel de correcciones propone el arreglo cuando se trata de un simbolo "
 "faltante."},

{"E202", "Falta ';'",
 "Toda sentencia de Nova termina en punto y coma. El parser lo detecta al ver "
 "que la siguiente sentencia empieza sin que la anterior haya cerrado.",
 "Agregue ';' al final de la sentencia anterior. El IDE puede insertarlo."},

{"E203", "Bloque sin cerrar",
 "Un '{' se abrio y nunca se cerro. El parser lo descubre al encontrar algo "
 "que no puede estar dentro de un bloque -- otra 'functio', o el final del "
 "archivo-- y el mensaje indica la linea donde ese bloque habia abierto.",
 "Agregue la '}' que falta. El panel de correcciones calcula, a partir de la "
 "sangria del codigo, en que linea corresponde cerrarlo."},

{"E204", "Falta ': tipo' en la declaracion",
 "Toda declaracion de Nova nombra su tipo: el lenguaje no lo infiere. En este "
 "punto el analizador solo admitia los dos puntos seguidos del tipo.",
 "Escriba ': tipo' despues del nombre, por ejemplo 'varia x : integer = 0;'."},

{"E205", "'aliter' sin 'si'",
 "Un bloque 'aliter' solo puede seguir a un 'si' o a un 'sin'. Suelto no "
 "corresponde a ninguna estructura de control.",
 "Agregue el 'si' correspondiente, o elimine el 'aliter'."},

{"E206", "Importacion tardia",
 "Las sentencias 'importa' deben ir al inicio del modulo, antes de cualquier "
 "declaracion, para que el enlazador resuelva los nombres en un solo recorrido.",
 "Mueva la linea 'importa' al encabezado del archivo."},

{"E207", "Falta el '{' del cuerpo",
 "El cuerpo de una funcion o de una estructura de control va siempre entre "
 "llaves; Nova no admite la forma de una sola sentencia sin bloque.",
 "Encierre el cuerpo entre '{' y '}'."},

{"E208", "Palabra reservada para el futuro",
 "El nombre esta reservado para versiones posteriores del lenguaje y no puede "
 "usarse como identificador, aunque hoy no tenga significado.",
 "Elija otro nombre para la variable o la funcion."},

{"E209", "Falta '->'",
 "La firma de una funcion declara su tipo de retorno despues de una flecha.",
 "Escriba '-> tipo' entre la lista de parametros y el cuerpo."},

/* --- Fase 3: analisis semantico ---------------------------------------- */
{"E301", "Nombre no declarado",
 "El identificador no existe en ningun ambito visible desde aqui. Puede ser un "
 "error de escritura, una declaracion posterior al uso, o un modulo que no se "
 "importo.",
 "Declare el nombre antes de usarlo, corrija la escritura, o agregue el "
 "'importa' del modulo correspondiente."},

{"E302", "Nombre duplicado",
 "Ya hay una declaracion con ese nombre en el mismo ambito. Nova no admite "
 "sobrecarga, asi que dos funciones tampoco pueden compartir nombre.",
 "Renombre una de las dos declaraciones, o mueva una a un ambito interior."},

{"E303", "Tipos incompatibles",
 "Los tipos de los operandos no corresponden a lo que exige el operador o la "
 "asignacion. Nova no convierte tipos de forma implicita: la comprobacion es "
 "estatica y estricta.",
 "Ajuste los tipos de los operandos, o use una variable intermedia del tipo "
 "correcto."},

{"E304", "Cantidad de argumentos incorrecta",
 "La llamada no pasa tantos argumentos como declara la funcion.",
 "Complete o quite argumentos hasta igualar la firma que se muestra en el "
 "mensaje."},

{"E305", "Tipo de argumento incorrecto",
 "El valor que se pasa no coincide con el tipo declarado para ese parametro.",
 "Pase un valor del tipo que declara el parametro."},

{"E306", "Condicion que no es 'veritas'",
 "Las condiciones de 'si', 'dum' y 'per' deben ser de tipo 'veritas'. Nova no "
 "trata los enteros como valores de verdad.",
 "Escriba una comparacion explicita, por ejemplo 'x != 0' en vez de 'x'."},

{"E307", "Indice que no es 'integer'",
 "Un arreglo solo se indexa con un valor entero.",
 "Use una expresion de tipo 'integer' como indice."},

{"E308", "Indice fuera de rango",
 "El indice es una constante y el compilador puede comprobar en tiempo de "
 "compilacion que cae fuera del arreglo.",
 "Corrija el indice: el rango valido va de 0 al tamano menos uno."},

{"E309", "Falta 'redde' en alguna ruta",
 "La funcion declara un tipo de retorno pero existe al menos un camino de "
 "ejecucion que termina sin ejecutar 'redde'.",
 "Agregue un 'redde' al final de la funcion, o en la rama que queda sin "
 "retorno."},

{"E310", "'rumpe'/'perge' fuera de un ciclo",
 "Estas sentencias solo tienen sentido dentro de 'dum' o 'per': el generador de "
 "codigo no tendria a que etiqueta saltar.",
 "Muevalas dentro del ciclo, o elimine la sentencia."},

{"E311", "Asignacion a una constante",
 "Una 'constans' se fija en su declaracion y el compilador la pliega en tiempo "
 "de compilacion; por eso no admite asignaciones posteriores.",
 "Declarela como 'varia' si de verdad necesita cambiar de valor."},

{"E312", "Retorno incompatible",
 "El valor que se retorna no coincide con el tipo declarado en la firma, o la "
 "funcion retorna un valor cuando declaro 'nihil'.",
 "Ajuste el valor de 'redde' al tipo declarado, o cambie la firma."},

{"E313", "No es una funcion",
 "Se intenta llamar a un nombre que designa una variable, una constante o un "
 "modulo.",
 "Use el nombre de una funcion, o quite los parentesis de la llamada."},

{"E314", "Uso incorrecto de arreglo",
 "Las reglas de arreglos de Nova son deliberadamente restrictivas: no se asigna "
 "un arreglo completo, no se retorna un arreglo, y una 'constans' no puede "
 "serlo. Todas nacen de que un arreglo vive en memoria y se pasa por "
 "referencia.",
 "Recorra el arreglo elemento por elemento, o pase el arreglo como parametro en "
 "vez de retornarlo."},

{"E315", "Recursion de cola invalida",
 "La funcion esta marcada '@cauda' pero la llamada recursiva no queda en "
 "posicion de cola, asi que la optimizacion no se puede aplicar.",
 "Deje la llamada recursiva como ultima operacion antes del 'redde', o quite la "
 "anotacion '@cauda'."},

{"E316", "Division entre cero constante",
 "El divisor es una constante igual a cero y el compilador lo detecta sin "
 "ejecutar el programa.",
 "Corrija el divisor, o use una variable y compruebe antes que no sea cero "
 "con un 'si'."},

{"E317", "Lista de inicializacion incorrecta",
 "La lista de valores no concuerda con la forma del arreglo: distinto tamano, "
 "distinto numero de dimensiones, o valores que no son constantes.",
 "Ajuste la lista al tamano y a las dimensiones declaradas, usando solo valores "
 "constantes."},

{"E318", "Tamano de arreglo invalido",
 "El tamano debe ser una constante entera positiva y el arreglo debe caber en "
 "la memoria de datos de CERBERO.",
 "Use un tamano constante y positivo que quepa en la memoria disponible."},

{"E319", "Uso incorrecto de una intrinseca",
 "Las funciones intrinsecas tienen restricciones adicionales: 'custodi' y "
 "'feistel' exigen ranura y ronda constantes entre 0 y 3, y 'longitudo' opera "
 "sobre arreglos o 'textus'.",
 "Pase constantes dentro del rango permitido y argumentos del tipo que la "
 "intrinseca acepta."},

{"E320", "Declaracion global no permitida",
 "Fuera de las funciones, Nova solo admite 'constans' y 'functio'. Las "
 "variables globales mutables quedaron fuera del lenguaje para que el modelo de "
 "memoria del generador de codigo sea predecible.",
 "Declare la variable dentro de una funcion, o conviertala en 'constans'."},

{"E321", "Uso incorrecto de 'nihil'",
 "'nihil' designa la ausencia de valor y solo puede aparecer como tipo de "
 "retorno; no es un tipo de dato que se pueda comparar, imprimir o declarar.",
 "Use un tipo concreto para el parametro o la variable."},

/* --- Fase 4: enlace y generacion --------------------------------------- */
{"E401", "Simbolo no resuelto",
 "El nombre calificado no existe en el modulo importado, o se referencio un "
 "simbolo de otro modulo sin pasar por el enlazador.",
 "Revise el nombre y que el modulo realmente exporte ese simbolo."},

{"E402", "Espacio de nombres duplicado",
 "Dos 'importa' declaran el mismo alias, asi que un nombre calificado seria "
 "ambiguo.",
 "Asigne alias distintos con 'ut <alias>'."},

{"E403", "Simbolo privado",
 "El simbolo esta marcado 'privatum' y no es visible fuera de su modulo.",
 "Quite 'privatum' en el modulo de origen si de verdad debe exportarse."},

{"E404", "Modulo no encontrado",
 "No se hallo el archivo del modulo importado en ninguna ruta de busqueda.",
 "Revise la ruta del 'importa' o agregue el directorio con la opcion -I."},

{"E405", "Falta 'principale'",
 "Para producir un ejecutable hace falta la funcion de entrada 'principale'. Un "
 "modulo de biblioteca se compila con -c.",
 "Agregue 'functio principale() -> integer', o compile el archivo como objeto "
 "con -c."},

{"E409", "Alias de modulo invalido",
 "La ruta del 'importa' no produce un nombre de modulo valido por si sola.",
 "Agregue 'ut <alias>' para darle un nombre explicito al modulo."},

{"E410", "Error de generacion de codigo",
 "La fase 4 no pudo ubicar un dato en memoria o codificar una operacion para "
 "CERBERO. Normalmente significa que el programa excede algun limite de la "
 "arquitectura.",
 "Reduzca el tamano de los datos o del codigo; el mensaje indica que recurso se "
 "agoto."},

/* --- Advertencias ------------------------------------------------------- */
{"W001", "Declaracion sin usar",
 "La variable o la constante se declara y nunca se lee. No impide compilar, "
 "pero casi siempre senala una linea olvidada o un nombre mal escrito.",
 "Elimine la declaracion, o use el valor donde corresponda."},

{"W002", "Declaracion ocultada",
 "Una declaracion interior tapa a otra del mismo nombre en un ambito exterior. "
 "El programa compila, pero el lector puede creer que se refiere a la otra.",
 "Renombre la declaracion interior."},

{"W003", "Codigo inalcanzable",
 "Las sentencias vienen despues de un 'redde', 'rumpe' o 'perge', de modo que "
 "el flujo nunca llega a ellas.",
 "Elimine el codigo muerto, o mueva la salida del bloque."},

{"W004", "Anotacion desconocida",
 "La anotacion no es ninguna de las que reconoce el compilador, asi que se "
 "descarta en silencio.",
 "Revise la escritura de la anotacion."},

{"W005", "Valor de retorno descartado",
 "Se llama a una funcion que retorna un valor y el valor se ignora.",
 "Asigne el resultado a una variable, o confirme que la llamada se hace solo "
 "por su efecto."},

{"W006", "Funcion obsoleta",
 "La funcion esta marcada '@obsoletum' en su declaracion.",
 "Use el reemplazo que indica el mensaje."},

{"W007", "Memoria de datos ajustada",
 "El marco de la funcion o el segmento de datos globales se acerca al limite "
 "que tiene CERBERO.",
 "Reduzca el tamano de los arreglos locales o globales."},

{"W008", "Region segura llena",
 "El codigo que usa la boveda de llaves no cabe en la region protegida.",
 "Mueva fuera de la region el codigo que no necesita la boveda."},

{"W009", "Programa mas grande que la IMEM",
 "El programa pasa de los 2048 bundles que admite la memoria de instrucciones "
 "de CERBERO. Compila, pero no se puede cargar en el procesador.",
 "Reduzca el tamano del programa, o active las optimizaciones del compilador."},

{"W032", "Advertencia general",
 "Aviso del compilador que no impide generar codigo.",
 "Revise el mensaje para el detalle."},
};

static const int catalogo_n = (int)(sizeof(catalogo) / sizeof(catalogo[0]));

const EntradaCatalogo *ide_catalogo_buscar(const char *codigo) {
    int i;
    if (codigo == NULL) return NULL;
    for (i = 0; i < catalogo_n; i++)
        if (strcmp(catalogo[i].codigo, codigo) == 0) return &catalogo[i];
    return NULL;
}

/*
 * La primera cifra del codigo identifica la fase que lo emite. Es la misma
 * convencion que usa diag.c para el resumen final del compilador.
 */
const char *ide_catalogo_fase(const char *codigo) {
    if (codigo == NULL || codigo[0] == '\0') return "desconocida";
    if (codigo[0] == 'W') return "advertencia";
    switch (codigo[1]) {
        case '1': return "lexico";
        case '2': return "sintactico";
        case '3': return "semantico";
        case '4': return "enlace";
        default:  return "desconocida";
    }
}

/* Lo usa la prueba del catalogo para recorrerlo completo. */
int ide_catalogo_total(void) { return catalogo_n; }
const EntradaCatalogo *ide_catalogo_indice(int i) {
    if (i < 0 || i >= catalogo_n) return NULL;
    return &catalogo[i];
}
