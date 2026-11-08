/*
 * Interfaz del IDE de Nova.
 *
 * Este archivo dibuja; no analiza. No hay aqui una lista de palabras
 * reservadas, ni reglas de tipos, ni un tokenizador: todo eso llega del nucleo
 * en C a traves del servidor. Hasta el coloreado del codigo se pinta con el
 * flujo de tokens que entrega el mismo yylex() que usa el compilador, de modo
 * que el editor no puede discrepar del compilador sobre que es una palabra
 * reservada o donde termina una cadena.
 *
 * El editor es un textarea con dos capas detras, alineadas al pixel:
 *
 *   capa pintada     el codigo con color, construida desde los tokens
 *   capa subrayado   el mismo texto en transparente, con el subrayado ondulado
 *                    sobre los rangos exactos que reporta el compilador
 *   textarea         texto transparente y cursor visible, recibe la escritura
 *
 * Las tres comparten fuente, tamano, interlineado y relleno (ver estilo.css).
 * Esa coincidencia es lo que hace que el color y el subrayado caigan justo
 * sobre el caracter que les corresponde.
 */

"use strict";

/* ------------------------------------------------------------- estado */

const App = {
  archivos: new Map(),      // nombre -> { contenido, guardado }
  actual: "editor.nv",
  diagnosticos: [],
  tokens: [],
  simbolos: [],
  etiquetas: [],
  flujo: null,
  flujoFuncion: 0,
  flujoBloque: null,
  correcciones: [],
  sugerencias: [],
  seleccion: 0,
  prefijo: "",
  metrica: { ancho: 8, alto: 21 },
  temporizador: null,
  analizando: false,
  pendiente: false,
  rangos: [],
};

const EJEMPLO = `# Programa de ejemplo en Nova.
# Escriba aqui: el analisis corre solo mientras escribe.

functio factorial(n : integer) -> integer {
    varia resultado : integer = 1;
    varia i : integer = 1;

    dum (i <= n) {
        resultado = resultado * i;
        i = i + 1;
    }

    redde resultado;
}

functio principale() -> integer {
    scribe(factorial(6));
    redde 0;
}
`;

/* --------------------------------------------------------- atajos DOM */

const $ = (id) => document.getElementById(id);
const codigo    = $("codigo");
const pintado   = $("pintado");
const subrayado = $("subrayado");
const lienzo    = $("lienzo");
const gutter    = $("gutter");
const popup     = $("popup");
const globo     = $("globo");

const hex = (n) => "0x" + n.toString(16).toUpperCase().padStart(4, "0");

function escapar(s) {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

/* ------------------------------------------------------ red con el nucleo */

async function pedir(ruta, cuerpo) {
  const opciones = cuerpo
    ? { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify(cuerpo) }
    : {};
  const r = await fetch("/api/" + ruta, opciones);
  return r.json();
}

function estado(texto, clase) {
  const p = $("pastilla-estado");
  p.textContent = texto;
  p.className = "pastilla" + (clase ? " " + clase : "");
}

/* ------------------------------------------- posiciones y metrica del texto */

/*
 * Offset absoluto donde empieza cada linea. Se recalcula con cada cambio del
 * texto y permite convertir entre (linea, columna) y posicion del textarea sin
 * recorrer la cadena completa cada vez.
 */
function iniciosDeLinea(texto) {
  const inicios = [0];
  for (let i = 0; i < texto.length; i++)
    if (texto[i] === "\n") inicios.push(i + 1);
  return inicios;
}

function aOffset(inicios, linea, columna) {
  const i = Math.min(Math.max(linea, 1), inicios.length) - 1;
  return inicios[i] + Math.max(columna - 1, 0);
}

function aLineaColumna(inicios, offset) {
  let bajo = 0, alto = inicios.length - 1;
  while (bajo < alto) {
    const medio = (bajo + alto + 1) >> 1;
    if (inicios[medio] <= offset) bajo = medio; else alto = medio - 1;
  }
  return { linea: bajo + 1, columna: offset - inicios[bajo] + 1 };
}

/* Mide una vez el ancho de caracter de la fuente monoespaciada. */
function medir() {
  const sonda = document.createElement("span");
  sonda.textContent = "0".repeat(50);
  sonda.style.cssText =
    "position:absolute;visibility:hidden;white-space:pre;" +
    getComputedStyle(codigo).font.replace(/^/, "font:") + ";";
  document.body.appendChild(sonda);
  App.metrica.ancho = sonda.getBoundingClientRect().width / 50;
  document.body.removeChild(sonda);
  App.metrica.alto = parseFloat(getComputedStyle(codigo).lineHeight);
}

function rellenoIzquierdo() {
  return parseFloat(getComputedStyle(codigo).paddingLeft);
}
function rellenoSuperior() {
  return parseFloat(getComputedStyle(codigo).paddingTop);
}

/* Pixeles donde cae una posicion del texto, dentro del lienzo visible. */
function puntoDe(linea, columna) {
  return {
    x: rellenoIzquierdo() + (columna - 1) * App.metrica.ancho - lienzo.scrollLeft,
    y: rellenoSuperior() + linea * App.metrica.alto - lienzo.scrollTop,
  };
}

/* Posicion del texto bajo un punto del raton. */
function posicionDesdePunto(clienteX, clienteY) {
  const caja = lienzo.getBoundingClientRect();
  const x = clienteX - caja.left + lienzo.scrollLeft - rellenoIzquierdo();
  const y = clienteY - caja.top + lienzo.scrollTop - rellenoSuperior();
  const linea = Math.floor(y / App.metrica.alto) + 1;
  const columna = Math.floor(x / App.metrica.ancho) + 1;
  return { linea, columna };
}

/* --------------------------------------------------------- capa pintada */

/*
 * Construye el HTML coloreado a partir del flujo de tokens.
 *
 * Los tramos entre tokens son espacios en blanco y comentarios: el lexer los
 * descarta y por eso no aparecen en la lista. Se emiten tal cual, marcando
 * como comentario lo que siga a un '#', que es la unica forma que tienen los
 * comentarios de Nova.
 */
function pintar(texto, tokens) {
  const inicios = iniciosDeLinea(texto);
  let html = "";
  let cursor = 0;

  const hueco = (hasta) => {
    if (hasta <= cursor) return;
    const tramo = texto.slice(cursor, hasta);
    // Se trata linea por linea para que un comentario no se coma el salto.
    const partes = tramo.split("\n");
    partes.forEach((parte, i) => {
      if (i > 0) html += "\n";
      const p = parte.indexOf("#");
      if (p < 0) html += escapar(parte);
      else html += escapar(parte.slice(0, p)) +
                   '<span class="t-comentario">' + escapar(parte.slice(p)) + "</span>";
    });
    cursor = hasta;
  };

  for (const t of tokens) {
    const desde = aOffset(inicios, t.linea, t.columna);
    const hasta = aOffset(inicios, t.fin_linea, t.fin_columna);
    if (desde < cursor) continue;
    hueco(desde);
    html += '<span class="t-' + t.categoria + '">' +
            escapar(texto.slice(desde, hasta)) + "</span>";
    cursor = hasta;
  }
  hueco(texto.length);

  // Un salto final garantiza que la ultima linea tenga altura.
  pintado.innerHTML = html + "\n";
}

/* ------------------------------------------------------ capa de subrayado */

/*
 * Mismo texto, en transparente, con los rangos de los diagnosticos envueltos
 * en spans que dibujan la onda. Los rangos vienen del compilador: linea,
 * columna y largo son los que calcularon el lexer, el parser o la fase
 * semantica, no una reconstruccion aproximada hecha aqui.
 */
function subrayar(texto, diagnosticos) {
  const inicios = iniciosDeLinea(texto);
  const marcas = [];

  for (const d of diagnosticos) {
    if (!d.linea || d.linea < 1) continue;

    const inicioLinea = aOffset(inicios, d.linea, 1);
    let finLinea = texto.indexOf("\n", inicioLinea);
    if (finLinea < 0) finLinea = texto.length;

    let desde = aOffset(inicios, d.linea, d.columna);
    let hasta = desde + Math.max(d.largo || 1, 1);

    /*
     * Varios diagnosticos apuntan a una columna que cae justo despues del
     * ultimo caracter de la linea: el ';' que falta se reporta donde deberia
     * haber estado, no sobre un caracter existente. Subrayar ese rango vacio
     * no dibujaria nada, que es justo el caso mas frecuente. Se corre la marca
     * al ultimo caracter de la linea, que es donde el usuario tiene que
     * escribir.
     */
    if (desde >= finLinea) {
      desde = Math.max(inicioLinea, finLinea - 1);
      hasta = finLinea;
    }
    if (hasta > finLinea) hasta = finLinea;
    if (hasta <= desde) {                      // linea vacia
      desde = inicioLinea;
      hasta = Math.min(inicioLinea + 1, texto.length);
    }
    if (hasta <= desde) continue;

    marcas.push({ desde, hasta, severidad: d.severidad, diag: d });
  }

  marcas.sort((a, b) => a.desde - b.desde);

  let html = "";
  let cursor = 0;
  const dibujadas = [];
  for (const m of marcas) {
    if (m.desde < cursor) continue;           // solapado: se queda el primero
    html += escapar(texto.slice(cursor, m.desde));
    html += '<span class="sub sub-' + m.severidad + '">' +
            escapar(texto.slice(m.desde, m.hasta)) + "</span>";
    cursor = m.hasta;
    dibujadas.push(m);
  }
  html += escapar(texto.slice(cursor));
  subrayado.innerHTML = html + "\n";

  /*
   * El globo se busca contra los rangos realmente dibujados, no contra la
   * columna cruda del diagnostico: despues del ajuste de arriba pueden no
   * coincidir, y el usuario apunta a lo que ve.
   */
  App.rangos = dibujadas;
}

/* ------------------------------------------------------------- gutter */

function dibujarGutter(texto) {
  const total = texto.split("\n").length;
  const porLinea = new Map();
  for (const d of App.diagnosticos) {
    const previo = porLinea.get(d.linea);
    if (previo !== "error") porLinea.set(d.linea, d.severidad);
  }
  const actual = aLineaColumna(iniciosDeLinea(texto), codigo.selectionStart).linea;

  let html = "";
  for (let i = 1; i <= total; i++) {
    let clase = "ln";
    const s = porLinea.get(i);
    if (s === "error") clase += " con-error";
    else if (s) clase += " con-aviso";
    if (i === actual) clase += " actual";
    html += '<div class="' + clase + '">' + i + "</div>";
  }
  gutter.innerHTML = html;
  gutter.scrollTop = lienzo.scrollTop;
}

/* --------------------------------------------------------- redibujado */

function redibujar() {
  const texto = codigo.value;
  pintar(texto, App.tokens);
  subrayar(texto, App.diagnosticos);
  dibujarGutter(texto);
  ajustarAlto(texto);
}

function ajustarAlto(texto) {
  // El textarea no hace scroll propio: crece y el lienzo es quien desplaza.
  const lineas = texto.split("\n").length + 1;
  const alto = lineas * App.metrica.alto + 2 * rellenoSuperior();
  codigo.style.height = alto + "px";
  pintado.style.height = alto + "px";
  subrayado.style.height = alto + "px";
}

/* --------------------------------------------------------- analisis */

function programarAnalisis(retardo = 260) {
  clearTimeout(App.temporizador);
  App.temporizador = setTimeout(analizar, retardo);
}

async function analizar() {
  if (App.analizando) { App.pendiente = true; return; }
  App.analizando = true;
  estado("analizando...", "trabajando");

  try {
    const r = await pedir("diagnosticar", {
      nombre: App.actual,
      contenido: codigo.value,
    });

    if (r.error) { estado(r.error, "mal"); return; }

    App.diagnosticos = r.diagnosticos || [];
    App.tokens = r.tokens || [];
    App.simbolos = r.simbolos || [];
    App.etiquetas = r.etiquetas || [];
    redibujar();
    mostrarProblemas();
    mostrarSimbolos();

    /*
     * Clase del archivo, como dato y no como falla: un modulo de biblioteca
     * sin 'principale' es perfectamente valido, y marcarlo en rojo seria
     * enganoso. Ver la nota en ide_diag.c.
     */
    const pe = r.punto_entrada;
    const chapa = $("pastilla-clase");
    if (pe && r.ok) {
      chapa.hidden = false;
      chapa.textContent = pe.clase;
      chapa.title = pe.nota;
    } else {
      chapa.hidden = true;
    }

    const e = r.resumen ? r.resumen.errores : 0;
    const a = r.resumen ? r.resumen.advertencias : 0;
    if (e > 0) estado(`${e} error${e === 1 ? "" : "es"}` + (a ? `, ${a} advertencia${a === 1 ? "" : "s"}` : ""), "mal");
    else if (a > 0) estado(`${a} advertencia${a === 1 ? "" : "s"}`, "aviso");
    else estado("sin errores", "ok");

    // Las correcciones solo tienen sentido si hay algo que corregir.
    if (e > 0) cargarCorrecciones(); else ponerCorrecciones([]);
  } catch (err) {
    estado("sin conexion con el servidor", "mal");
  } finally {
    App.analizando = false;
    if (App.pendiente) { App.pendiente = false; programarAnalisis(60); }
  }
}

/* ------------------------------------------------- panel de problemas */

function mostrarProblemas() {
  const v = $("v-problemas");
  const c = $("c-problemas");
  const n = App.diagnosticos.length;
  const errores = App.diagnosticos.filter((d) => d.severidad === "error").length;

  c.textContent = n;
  c.className = "contador" + (errores ? " hay" : n ? " aviso" : "");

  if (!n) {
    v.innerHTML = '<div class="vacio"><span class="grande">&#10003;</span>' +
                  "El archivo analiza sin errores ni advertencias.</div>";
    return;
  }

  v.innerHTML = App.diagnosticos.map((d, i) => `
    <div class="fila ${d.severidad}" data-ir="${i}">
      <span class="pos">${d.linea}:${d.columna}</span>
      <div class="cuerpo">
        <div class="linea1">
          <span class="codigo">${escapar(d.codigo)}</span>
          <span class="mensaje">${escapar(d.mensaje)}</span>
          <span class="codigo">${escapar(d.fase)}</span>
        </div>
        ${d.explicacion ? `<div class="detalle">${escapar(d.explicacion)}</div>` : ""}
        ${d.remedio ? `<div class="remedio">${escapar(d.remedio)}</div>` : ""}
      </div>
    </div>`).join("");

  v.querySelectorAll(".fila").forEach((f) => {
    f.onclick = () => {
      const d = App.diagnosticos[+f.dataset.ir];
      irA(d.linea, d.columna);
    };
  });
}

/* ---------------------------------------------- panel de correcciones */

async function cargarCorrecciones() {
  const r = await pedir("arreglar", { nombre: App.actual, contenido: codigo.value });
  ponerCorrecciones(r.correcciones || []);
}

function ponerCorrecciones(lista) {
  App.correcciones = lista;
  const v = $("v-correcciones");
  const c = $("c-correcciones");
  c.textContent = lista.length;
  c.className = "contador" + (lista.length ? " aviso" : "");

  if (!lista.length) {
    v.innerHTML = '<div class="vacio"><span class="grande">&#9881;</span>' +
                  "No hay correcciones automaticas que proponer.<br>" +
                  "Aparecen cuando falta un ';', una llave o un parentesis.</div>";
    return;
  }

  v.innerHTML = lista.map((f, i) => {
    const e = f.ediciones[0];
    return `
    <div class="fila" data-ir="${i}">
      <span class="pos">${e.linea}:${e.columna}</span>
      <div class="cuerpo">
        <div class="linea1">
          <span class="codigo">${escapar(f.codigo)}</span>
          <span class="mensaje">${escapar(f.titulo)}</span>
          <span class="sello sello-${f.confianza}">confianza ${escapar(f.confianza)}</span>
        </div>
        <div class="detalle">${escapar(f.descripcion)}</div>
      </div>
      <button class="btn-aplicar" data-aplicar="${i}">Aplicar</button>
    </div>`;
  }).join("");

  v.querySelectorAll("[data-aplicar]").forEach((b) => {
    b.onclick = (ev) => { ev.stopPropagation(); aplicarCorreccion(+b.dataset.aplicar); };
  });
  v.querySelectorAll(".fila").forEach((f) => {
    f.onclick = () => {
      const e = App.correcciones[+f.dataset.ir].ediciones[0];
      irA(e.linea, e.columna);
    };
  });
}

/*
 * Aplica una correccion y vuelve a analizar. Se aplica de una en una a
 * proposito: corregir un error cambia las posiciones del resto del archivo y
 * suele revelar o eliminar otros diagnosticos, asi que el siguiente arreglo
 * debe calcularse sobre el texto ya corregido y no sobre el analisis viejo.
 */
function aplicarCorreccion(indice) {
  const f = App.correcciones[indice];
  if (!f) return;
  const e = f.ediciones[0];

  const lineas = codigo.value.split("\n");
  while (lineas.length < e.linea) lineas.push("");

  const i = e.linea - 1;
  let l = lineas[i];
  const col = e.columna - 1;
  if (l.length < col) l = l + " ".repeat(col - l.length);
  lineas[i] = l.slice(0, col) + e.insertar + l.slice(col + (e.borrar || 0));

  codigo.value = lineas.join("\n");
  marcarSucio();
  irA(e.linea, e.columna + e.insertar.length);
  analizar();
}

/* -------------------------------------------------- panel de simbolos */

function mostrarSimbolos() {
  const v = $("v-simbolos");
  const c = $("c-simbolos");
  const propios = App.simbolos.filter((s) => s.region !== "intrinseca");
  c.textContent = propios.length;
  c.className = "contador";

  if (!propios.length) {
    v.innerHTML = '<div class="vacio"><span class="grande">&#9638;</span>' +
                  "La tabla de simbolos aparece cuando el archivo analiza sin errores.</div>";
    return;
  }

  v.innerHTML = `
    <table class="datos">
      <thead><tr>
        <th>Nombre</th><th>Clase</th><th>Ambito</th><th>Tipo</th>
        <th>Region</th><th>Direccion</th><th>Respecto de R14</th>
        <th>Bytes</th><th>Declarado</th>
      </tr></thead>
      <tbody>
      ${propios.map((s) => `
        <tr data-linea="${s.linea}" data-columna="${s.columna}">
          <td class="nom">${escapar(s.nombre)}</td>
          <td class="cls">${escapar(s.clase)}</td>
          <td>${escapar(s.ambito)}</td>
          <td class="tip">${escapar(s.tipo)}</td>
          <td>${s.region || "&mdash;"}</td>
          <td class="dir">${s.direccion === null ? "&mdash;" : hex(s.direccion)}</td>
          <td class="off">${s.desplazamiento_r14 === null ? "&mdash;"
              : "r14" + (s.desplazamiento_r14 >= 0 ? "+" : "") + s.desplazamiento_r14}</td>
          <td class="off">${s.bytes || "&mdash;"}</td>
          <td class="off">${s.linea ? s.linea + ":" + s.columna : "&mdash;"}</td>
        </tr>`).join("")}
      </tbody>
    </table>`;

  /*
   * Los puntos de salto, debajo de los simbolos. No son nombres del programa
   * fuente sino etiquetas que genera el compilador para condicionales y
   * ciclos, con la direccion que les asigno la resolucion de saltos.
   */
  if (App.etiquetas && App.etiquetas.length) {
    v.insertAdjacentHTML("beforeend", `
      <h3 class="titulo-seccion">Puntos de salto y etiquetas resueltas
        <span class="contador">${App.etiquetas.length}</span></h3>
      <table class="datos">
        <thead><tr>
          <th>Etiqueta</th><th>Region</th><th>Direccion</th><th>Bundle</th>
        </tr></thead>
        <tbody>
        ${App.etiquetas.map((e) => `
          <tr>
            <td class="nom">${escapar(e.nombre)}</td>
            <td>${e.region}</td>
            <td class="dir">${hex(e.direccion)}</td>
            <td class="off">${e.bundle === null ? "&mdash;" : e.bundle}</td>
          </tr>`).join("")}
        </tbody>
      </table>`);
  }

  v.querySelectorAll("tbody tr").forEach((t) => {
    t.onclick = () => {
      const l = +t.dataset.linea;
      if (l > 0) irA(l, +t.dataset.columna);
    };
  });
}

/* ------------------------------------------- panel de flujo (Iteracion 2) */

/*
 * Reparte los bloques en niveles para dibujarlos.
 *
 * El nivel de un bloque es el camino mas largo desde la entrada contando solo
 * aristas HACIA ADELANTE. Las aristas de regreso -- las que cierran un lazo--
 * se excluyen del calculo: si contaran, el nivel de un bloque dentro de un
 * ciclo no tendria un valor finito. Asi un 'si/aliter' queda con sus dos ramas
 * lado a lado y el lazo se dibuja como un arco que sube.
 */
function nivelarBloques(lista) {
  const nivel = lista.map(() => 0);
  for (const b of lista) {
    for (const s of b.sucesores) {
      if (s <= b.id) continue;                 // arista de regreso
      if (nivel[s] < nivel[b.id] + 1) nivel[s] = nivel[b.id] + 1;
    }
  }
  const filas = [];
  lista.forEach((b) => {
    (filas[nivel[b.id]] = filas[nivel[b.id]] || []).push(b);
  });
  return { nivel, filas };
}

const NODO_W = 152, NODO_H = 46, SEP_X = 30, SEP_Y = 52, MARGEN = 26;

function dibujarGrafo(fn) {
  const lienzo = $("flujo-lienzo");
  const lista = fn.lista;
  if (!lista.length) { lienzo.innerHTML = '<div class="vacio">Sin bloques.</div>'; return; }

  const { filas } = nivelarBloques(lista);
  const pos = {};
  let anchoMax = 0;

  filas.forEach((fila, nv) => {
    if (!fila) return;
    const ancho = fila.length * NODO_W + (fila.length - 1) * SEP_X;
    anchoMax = Math.max(anchoMax, ancho);
    fila.forEach((b, k) => {
      pos[b.id] = { x: k * (NODO_W + SEP_X) - ancho / 2, y: nv * (NODO_H + SEP_Y) };
    });
  });

  const W = anchoMax + 2 * MARGEN + 90;
  const H = filas.length * (NODO_H + SEP_Y) + 2 * MARGEN;
  const cx = W / 2;
  Object.values(pos).forEach((p) => { p.x += cx; p.y += MARGEN; });

  const aristas = [];
  for (const b of lista) {
    b.sucesores.forEach((s, idx) => {
      const a = pos[b.id], d = pos[s];
      if (!a || !d) return;
      const regreso = s <= b.id;
      const x1 = a.x + NODO_W / 2, y1 = a.y + NODO_H;
      const x2 = d.x + NODO_W / 2, y2 = d.y;

      let camino;
      if (regreso) {
        // Arco por fuera, para no cruzar los nodos intermedios.
        const lado = x1 + NODO_W / 2 + 34;
        camino = `M ${x1} ${y1} C ${lado} ${y1 + 16}, ${lado} ${y2 - 16}, ${x2} ${y2 - 2}`;
      } else {
        const medio = (y1 + y2) / 2;
        camino = `M ${x1} ${y1} C ${x1} ${medio}, ${x2} ${medio}, ${x2} ${y2 - 2}`;
      }
      // En un condicional, el primer sucesor es el destino del salto y el
      // segundo la caida; se marca para poder leerlos distinto.
      const clase = regreso ? "regreso" : (b.fin === "condicional" && idx === 1 ? "falso" : "");
      aristas.push(`<path class="arista ${clase}" d="${camino}"/>`);
    });
  }

  const nodos = lista.map((b) => {
    const p = pos[b.id];
    const clases = ["nodo"];
    if (b.entrada) clases.push("entrada");
    if (!b.alcanzable) clases.push("muerto");
    if (b.profundidad_ciclo > 0) clases.push("lazo");
    if (App.flujoBloque === b.id) clases.push("sel");
    const etq = b.etiqueta ? ` ${b.etiqueta}` : "";
    return `<g class="${clases.join(" ")}" data-b="${b.id}" transform="translate(${p.x},${p.y})">
      <rect width="${NODO_W}" height="${NODO_H}"/>
      <text class="n-tit" x="10" y="19">B${b.id}${escapar(etq)}</text>
      <text class="n-sub" x="10" y="34">${b.instrucciones} inst · ${escapar(b.fin)}</text>
    </g>`;
  }).join("");

  lienzo.innerHTML = `
    <svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
      <defs>
        <marker id="punta" markerWidth="9" markerHeight="9" refX="8" refY="3"
                orient="auto" markerUnits="strokeWidth">
          <path d="M0,0 L0,6 L8,3 z" fill="#4a5570"/>
        </marker>
        <marker id="punta-lazo" markerWidth="9" markerHeight="9" refX="8" refY="3"
                orient="auto" markerUnits="strokeWidth">
          <path d="M0,0 L0,6 L8,3 z" fill="#e2b341"/>
        </marker>
      </defs>
      ${aristas.join("")}
      ${nodos}
    </svg>
    <div class="leyenda">
      <span><i></i>flujo normal</span>
      <span><i class="regreso"></i>arista de regreso (lazo)</span>
      <span><i class="caja"></i>entrada</span>
      <span><i class="muerta"></i>inalcanzable</span>
    </div>`;

  lienzo.querySelectorAll(".nodo").forEach((n) => {
    n.onclick = () => { App.flujoBloque = +n.dataset.b; dibujarGrafo(fn); detalleBloque(fn); };
  });
}

function detalleBloque(fn) {
  const caja = $("flujo-detalle");
  const b = fn.lista.find((x) => x.id === App.flujoBloque);
  if (!b) {
    caja.innerHTML = '<div class="vacio">Clic en un bloque para ver su codigo.</div>';
    return;
  }
  const lista = (v) => v.length ? v.map((x) => "B" + x).join(", ") : "ninguno";
  /*
   * Los cuatro conjuntos del analisis de vivacidad. Se muestran siempre, aunque
   * esten vacios: un VIVO_SAL vacio es informacion -- quiere decir que de ese
   * bloque no sale vivo ningun valor -- y esconderlo haria pensar que el
   * analisis no corrio.
   */
  const nombres = (v) => (v && v.length) ? v.map(escapar).join(", ") : "∅";
  const conjuntos = b.vivo_ent === undefined ? "" : `
    <table class="conjuntos">
      <tr><th>USO</th><td>${nombres(b.uso)}</td></tr>
      <tr><th>DEF</th><td>${nombres(b.def)}</td></tr>
      <tr class="sep"><th>VIVO_ENT</th><td>${nombres(b.vivo_ent)}</td></tr>
      <tr><th>VIVO_SAL</th><td>${nombres(b.vivo_sal)}</td></tr>
    </table>`;

  caja.innerHTML = `
    <h4>B${b.id}${b.etiqueta ? " (" + escapar(b.etiqueta) + ")" : ""}</h4>
    <div class="meta">
      <span>${b.instrucciones} instrucciones</span>
      <span>termina en ${escapar(b.fin)}</span>
      ${b.entrada ? "<span>entrada</span>" : ""}
      ${b.alcanzable ? "" : "<span>inalcanzable</span>"}
      ${b.profundidad_ciclo > 0 ? `<span>en lazo (nivel ${b.profundidad_ciclo})</span>` : ""}
      <span>predecesores: ${lista(b.predecesores)}</span>
      <span>sucesores: ${lista(b.sucesores)}</span>
    </div>
    ${conjuntos}
    <pre>${b.codigo.map((c) => {
      const clase = c.muerta === 1 ? ' class="tac-muerta"'
                  : c.muerta === 2 ? ' class="tac-sinuso"' : "";
      return `<span${clase}>` +
        (c.linea > 0 ? `<b data-l="${c.linea}" data-c="${c.columna}">${String(c.linea).padStart(3)}</b>  `
                     : "  ·  ") + escapar(c.texto) + "</span>";
    }).join("\n")}</pre>
    ${b.codigo.some((c) => c.muerta)
      ? '<div class="nota-muerta">Lo tachado es lo que elimina <code>-O1</code>: '
        + 'el analisis de vivacidad dice que ese valor no se vuelve a leer.</div>'
      : ""}`;
  caja.querySelectorAll("b[data-l]").forEach((e) => {
    e.onclick = () => irA(+e.dataset.l, +e.dataset.c || 1);
  });
}

async function construirFlujo() {
  const boton = $("btn-flujo");
  boton.disabled = true;
  boton.textContent = "Construyendo...";
  try {
    const r = await pedir("bloques", { nombre: App.actual, contenido: codigo.value });
    App.flujo = r;
    App.flujoBloque = null;
    mostrarFlujo();
  } finally {
    boton.disabled = false;
    boton.textContent = "Construir grafo";
  }
}

function mostrarFlujo() {
  const r = App.flujo;
  const sel = $("flujo-funcion");
  const datos = $("flujo-datos");
  const c = $("c-flujo");

  if (!r || !r.ok) {
    sel.innerHTML = "";
    datos.innerHTML = "";
    c.textContent = "0";
    c.className = "contador";
    $("flujo-lienzo").innerHTML =
      `<div class="vacio"><span class="grande">⌁</span>${escapar(
        (r && r.motivo) || "Pulse «Construir grafo» para analizar el archivo.")}</div>`;
    $("flujo-detalle").innerHTML = "";
    return;
  }

  c.textContent = r.resumen.bloques;
  c.className = "contador" + (r.resumen.inalcanzables ? " hay" : "");

  if (App.flujoFuncion >= r.funciones.length) App.flujoFuncion = 0;
  sel.innerHTML = r.funciones.map((f, i) =>
    `<option value="${i}"${i === App.flujoFuncion ? " selected" : ""}>${escapar(f.nombre)} (${f.bloques} bloques)</option>`).join("");
  sel.onchange = () => {
    App.flujoFuncion = +sel.value;
    App.flujoBloque = null;
    mostrarFlujo();
  };

  const fn = r.funciones[App.flujoFuncion];
  datos.innerHTML =
    `<span>${fn.bloques} bloques</span><span>${fn.aristas} aristas</span>` +
    (fn.inalcanzables ? `<span class="alerta">${fn.inalcanzables} inalcanzable${fn.inalcanzables === 1 ? "" : "s"}</span>` : "") +
    (fn.iteraciones ? `<span>vivacidad: ${fn.nombres_analizados} nombres, punto fijo en ${fn.iteraciones} pasada${fn.iteraciones === 1 ? "" : "s"}</span>` : "") +
    (r.resumen.sobran ? `<span class="alerta">-O1 quitaria ${r.resumen.sobran} instrucciones</span>` : "") +
    `<span>total: ${r.resumen.bloques} bloques en ${r.resumen.funciones} funciones</span>`;

  dibujarGrafo(fn);
  detalleBloque(fn);
}

/* ---------------------------------------------------- panel de clones */

async function buscarClones() {
  const boton = $("btn-clones");
  boton.disabled = true;
  boton.textContent = "Buscando...";

  try {
    const archivos = [{ nombre: App.actual, contenido: codigo.value }];

    // Los demas buffers abiertos, con su contenido actual.
    for (const [nombre, f] of App.archivos)
      if (nombre !== App.actual) archivos.push({ nombre, contenido: f.contenido });

    if ($("clones-todo").checked) {
      const lista = await pedir("archivos");
      const yaEstan = new Set(archivos.map((a) => a.nombre));
      for (const ruta of (lista.archivos || []).slice(0, 60)) {
        if (yaEstan.has(ruta)) continue;
        const r = await pedir("archivo?ruta=" + encodeURIComponent(ruta));
        if (r.contenido !== undefined)
          archivos.push({ nombre: ruta, contenido: r.contenido });
      }
    }

    const r = await pedir("clones", {
      archivos,
      min_tokens: +$("clones-min").value || 20,
      umbral: +$("clones-umbral").value || 0.8,
    });
    mostrarClones(r);
  } finally {
    boton.disabled = false;
    boton.textContent = "Buscar clones";
  }
}

const EXPLICA_TIPO = {
  I: "Codigo identico. Solo cambian el formato, los comentarios y el archivo " +
     "donde esta.",
  II: "Misma estructura con los nombres cambiados. Si el renombrado es " +
      "consistente, cada identificador de un lado corresponde siempre al mismo " +
      "del otro.",
  III: "Copia con modificaciones: se agregaron o quitaron sentencias o " +
       "variables. La similitud mide cuanto del codigo sobrevivio a esos cambios.",
};

function mostrarClones(r) {
  const v = $("clones-resultado");
  const c = $("c-clones");

  if (r.error) { v.innerHTML = `<div class="vacio">${escapar(r.error)}</div>`; return; }

  const res = r.resumen || {};
  c.textContent = res.total || 0;
  c.className = "contador" + (res.total ? " aviso" : "");

  let html = `
    <div class="resumen-clones">
      <div class="tarjeta t1"><span class="n">${res.tipo_I || 0}</span><span class="e">Tipo I</span></div>
      <div class="tarjeta t2"><span class="n">${res.tipo_II || 0}</span><span class="e">Tipo II</span></div>
      <div class="tarjeta t3"><span class="n">${res.tipo_III || 0}</span><span class="e">Tipo III</span></div>
      <div class="tarjeta"><span class="n">${res.unidades || 0}</span><span class="e">unidades comparadas</span></div>
      <div class="tarjeta"><span class="n">${(r.archivos || []).length}</span><span class="e">archivos</span></div>
    </div>`;

  if (!r.clones || !r.clones.length) {
    html += '<div class="vacio"><span class="grande">&#10003;</span>' +
            "No se encontraron clones con estos parametros.</div>";
    v.innerHTML = html;
    return;
  }

  html += r.clones.map((cl) => {
    const t = cl.tipo === "I" ? "t1" : cl.tipo === "II" ? "t2" : "t3";
    const lado = (l) => `
      <div class="lado" data-archivo="${escapar(l.archivo)}" data-linea="${l.linea_inicio}">
        <div class="arch">${escapar(l.archivo)}</div>
        <div class="uni">${escapar(l.unidad)}</div>
        <div class="loc">lineas ${l.linea_inicio}&ndash;${l.linea_fin} &middot; ${l.tokens} tokens</div>
      </div>`;
    return `
      <div class="clon ${t}">
        <div class="cab">
          <span class="tipo">Clon Tipo ${cl.tipo}</span>
          <span class="met">similitud ${(cl.similitud * 100).toFixed(1)}%</span>
          <span class="met">tramo contiguo ${cl.racha_contigua} tokens</span>
          ${cl.tipo === "II" ? `<span class="met">renombrado ${escapar(cl.renombrado)}</span>
            <span class="met">${cl.identificadores_cambiados} nombres cambiados</span>` : ""}
          ${cl.entre_archivos ? '<span class="met">entre archivos</span>'
                              : '<span class="met">mismo archivo</span>'}
          ${cl.archivo_completo ? '<span class="met">archivo completo</span>' : ""}
        </div>
        <div class="lados">${lado(cl.a)}${lado(cl.b)}</div>
        <div class="nota">${escapar(EXPLICA_TIPO[cl.tipo] || "")}</div>
      </div>`;
  }).join("");

  v.innerHTML = html;

  v.querySelectorAll(".lado").forEach((l) => {
    l.onclick = async () => {
      await abrirArchivo(l.dataset.archivo);
      irA(+l.dataset.linea, 1);
    };
  });
}

/* ---------------------------------------------------- autocompletado */

async function pedirSugerencias() {
  const pos = aLineaColumna(iniciosDeLinea(codigo.value), codigo.selectionStart);
  const r = await pedir("completar", {
    nombre: App.actual,
    contenido: codigo.value,
    linea: pos.linea,
    columna: pos.columna,
  });
  if (r.error) return;

  App.sugerencias = r.sugerencias || [];
  App.prefijo = r.prefijo || "";
  App.seleccion = 0;
  if (App.sugerencias.length) abrirPopup(pos); else cerrarPopup();
}

function abrirPopup(pos) {
  const lista = $("popup-lista");

  lista.innerHTML = App.sugerencias.map((s, i) => {
    const n = App.prefijo.length;
    const resaltado = n > 0
      ? "<b>" + escapar(s.nombre.slice(0, n)) + "</b>" + escapar(s.nombre.slice(n))
      : escapar(s.nombre);
    return `<li class="${i === 0 ? "sel" : ""}" data-i="${i}">
              <span class="nom">${resaltado}</span>
              <span class="cls">${escapar(s.clase)}</span>
            </li>`;
  }).join("");

  lista.querySelectorAll("li").forEach((li) => {
    li.onmouseenter = () => seleccionar(+li.dataset.i);
    li.onmousedown = (e) => { e.preventDefault(); aceptarSugerencia(+li.dataset.i); };
  });

  // Se ancla al inicio de la palabra que se esta escribiendo.
  const p = puntoDe(pos.linea, pos.columna - App.prefijo.length);
  const caja = lienzo.getBoundingClientRect();
  popup.hidden = false;

  const alto = popup.offsetHeight;
  const arriba = p.y + alto > caja.height;
  popup.style.left = Math.max(4, Math.min(p.x, caja.width - popup.offsetWidth - 8)) + "px";
  popup.style.top = (arriba ? p.y - alto - App.metrica.alto : p.y) + "px";

  seleccionar(0);
}

function cerrarPopup() {
  popup.hidden = true;
  App.sugerencias = [];
}

function seleccionar(i) {
  if (!App.sugerencias.length) return;
  App.seleccion = (i + App.sugerencias.length) % App.sugerencias.length;
  const lista = $("popup-lista");
  lista.querySelectorAll("li").forEach((li, k) =>
    li.classList.toggle("sel", k === App.seleccion));
  const activo = lista.children[App.seleccion];
  if (activo) activo.scrollIntoView({ block: "nearest" });

  const s = App.sugerencias[App.seleccion];
  $("popup-doc").innerHTML =
    (s.detalle ? `<span class="firma">${escapar(s.detalle)}</span>` : "") +
    (s.documentacion && !s.documentacion.startsWith("DMEM") && !s.documentacion.startsWith("IMEM")
      ? escapar(s.documentacion)
      : "") +
    (s.documentacion && (s.documentacion.startsWith("DMEM") || s.documentacion.startsWith("IMEM"))
      ? `<span class="dir">${escapar(s.documentacion)}</span>` : "");
}

/*
 * Inserta la sugerencia reemplazando el prefijo que el usuario ya escribio.
 * Las plantillas traen marcadores ${n:texto}; se limpian al insertar y el
 * cursor queda en el primero de ellos.
 */
function aceptarSugerencia(i) {
  const s = App.sugerencias[i !== undefined ? i : App.seleccion];
  if (!s) return;

  const fin = codigo.selectionStart;
  const inicio = fin - App.prefijo.length;
  const sangria = sangriaDeLinea(codigo.value, inicio);

  let texto = s.insertar;
  let hueco = null;

  if (s.es_plantilla) {
    texto = texto.split("\n").map((l, k) => (k === 0 ? l : sangria + l)).join("\n");
    const r = expandirPlantilla(texto);
    texto = r.texto;
    hueco = r.hueco;
  }

  codigo.value = codigo.value.slice(0, inicio) + texto + codigo.value.slice(fin);

  if (hueco) {
    /*
     * El hueco queda SELECCIONADO, no solo marcado con el cursor. Si solo se
     * moviera el cursor, el texto de relleno ("condicion") se quedaria en el
     * programa y lo que el usuario escriba se le pondria al lado. Dejandolo
     * seleccionado, la primera tecla lo reemplaza, que es como se comporta
     * cualquier editor.
     */
    codigo.selectionStart = inicio + hueco.inicio;
    codigo.selectionEnd = inicio + hueco.inicio + hueco.largo;
  } else {
    codigo.selectionStart = codigo.selectionEnd = inicio + texto.length;
  }

  cerrarPopup();
  marcarSucio();
  redibujar();
  programarAnalisis();
}

/*
 * Quita un nivel de sangria a la linea del cursor cuando lo unico que tiene es
 * la llave de cierre recien escrita. Sin esto, el auto-sangrado de Enter deja
 * cada '}' un nivel mas adentro de lo que corresponde, y la sangria es
 * justamente lo que el corrector automatico lee para decidir donde va una
 * llave que falta.
 */
function desangrarCierre() {
  const i = codigo.selectionStart;
  const inicio = codigo.value.lastIndexOf("\n", i - 1) + 1;
  const antes = codigo.value.slice(inicio, i);
  if (!/^[ \t]+\}$/.test(antes)) return;

  const quitar = antes.startsWith("    ") ? 4 : antes.length - 1;
  if (quitar <= 0) return;
  codigo.value = codigo.value.slice(0, inicio) +
                 antes.slice(quitar) +
                 codigo.value.slice(i);
  codigo.selectionStart = codigo.selectionEnd = i - quitar;
}

/*
 * Expande los marcadores de una plantilla.
 *
 * El formato es ${n:relleno} para un hueco con texto por omision y ${0} para
 * donde queda el cursor al final. Devuelve el texto ya limpio y, si hay hueco,
 * su posicion y largo dentro de ese texto, para poder seleccionarlo.
 *
 * Las posiciones se calculan sobre el texto FINAL, no sobre la plantilla: cada
 * marcador que se reemplaza corre todo lo que viene despues, asi que medir
 * sobre el original deja el hueco desplazado.
 */
function expandirPlantilla(plantilla) {
  const re = /\$\{(\d+)(?::([^}]*))?\}/g;
  let salida = "", ultimo = 0, hueco = null, cursorCero = -1, m;

  while ((m = re.exec(plantilla)) !== null) {
    salida += plantilla.slice(ultimo, m.index);
    const numero = m[1];
    const relleno = m[2] !== undefined ? m[2] : "";

    if (numero === "0") {
      if (cursorCero < 0) cursorCero = salida.length;
    } else if (hueco === null && relleno.length > 0) {
      hueco = { inicio: salida.length, largo: relleno.length };
    }

    salida += relleno;
    ultimo = m.index + m[0].length;
  }
  salida += plantilla.slice(ultimo);

  // Sin huecos con relleno, el cursor va donde marque ${0}.
  if (hueco === null && cursorCero >= 0) hueco = { inicio: cursorCero, largo: 0 };
  return { texto: salida, hueco };
}

function sangriaDeLinea(texto, offset) {
  const inicio = texto.lastIndexOf("\n", offset - 1) + 1;
  const m = texto.slice(inicio).match(/^[ \t]*/);
  return m ? m[0] : "";
}

/* ------------------------------------------------- globo sobre el error */

function mostrarGlobo(ev) {
  const pos = posicionDesdePunto(ev.clientX, ev.clientY);
  const inicios = iniciosDeLinea(codigo.value);
  if (pos.linea < 1 || pos.linea > inicios.length) { globo.hidden = true; return; }

  const offset = aOffset(inicios, pos.linea, pos.columna);
  const marca = (App.rangos || []).find((m) => offset >= m.desde && offset < m.hasta);
  const d = marca && marca.diag;

  if (!d) { globo.hidden = true; return; }

  // Dos superposiciones a la vez estorban; manda la que esta bajo el puntero.
  cerrarPopup();

  globo.className = "globo" + (d.severidad === "error" ? "" : " aviso");
  globo.innerHTML = `
    <div class="cab">
      <span class="cod">${escapar(d.codigo)}</span>
      <span class="tit">${escapar(d.titulo || d.severidad)}</span>
      <span class="fase">fase ${escapar(d.fase)}</span>
    </div>
    <div class="msj">${escapar(d.mensaje)}</div>
    ${d.explicacion ? `<div class="exp">${escapar(d.explicacion)}</div>` : ""}
    ${d.remedio ? `<div class="rem">${escapar(d.remedio)}</div>` : ""}`;

  globo.hidden = false;

  const caja = lienzo.getBoundingClientRect();
  const inicioMarca = aLineaColumna(inicios, marca.desde);
  const p = puntoDe(inicioMarca.linea, inicioMarca.columna);
  let x = p.x;
  if (x + globo.offsetWidth > caja.width - 10) x = caja.width - globo.offsetWidth - 10;
  globo.style.left = Math.max(6, x) + "px";
  globo.style.top = (p.y + 6) + "px";
}

/* --------------------------------------------------------- navegacion */

function irA(linea, columna) {
  const inicios = iniciosDeLinea(codigo.value);
  const offset = aOffset(inicios, linea, columna || 1);
  codigo.focus();
  codigo.selectionStart = codigo.selectionEnd = offset;

  const y = (linea - 1) * App.metrica.alto;
  const visible = lienzo.clientHeight;
  if (y < lienzo.scrollTop || y > lienzo.scrollTop + visible - App.metrica.alto * 2)
    lienzo.scrollTop = Math.max(0, y - visible / 3);

  dibujarGutter(codigo.value);
}

/* ------------------------------------------------------------ archivos */

function marcarSucio() {
  const f = App.archivos.get(App.actual);
  if (f) { f.contenido = codigo.value; f.guardado = false; }
  $("sucio").hidden = false;
  dibujarListaAbiertos();
}

async function abrirArchivo(nombre) {
  if (nombre === App.actual) return;

  // Guarda el buffer actual en memoria antes de cambiar.
  App.archivos.set(App.actual, {
    contenido: codigo.value,
    guardado: App.archivos.get(App.actual)?.guardado ?? false,
  });

  if (!App.archivos.has(nombre)) {
    const r = await pedir("archivo?ruta=" + encodeURIComponent(nombre));
    if (r.error) { estado("no se pudo abrir " + nombre, "mal"); return; }
    App.archivos.set(nombre, { contenido: r.contenido, guardado: true });
  }

  App.actual = nombre;
  codigo.value = App.archivos.get(nombre).contenido;
  $("nombre-archivo").value = nombre;
  $("sucio").hidden = App.archivos.get(nombre).guardado;

  App.diagnosticos = []; App.tokens = []; App.simbolos = [];
  lienzo.scrollTop = 0;
  redibujar();
  dibujarListaAbiertos();
  marcarArchivoActivo();
  analizar();
}

async function cargarListaArchivos() {
  const r = await pedir("archivos");
  const ul = $("lista-archivos");
  const filtro = $("filtro-archivos").value.toLowerCase();
  const lista = (r.archivos || []).filter((a) => a.toLowerCase().includes(filtro));

  ul.innerHTML = lista.map((a) =>
    `<li data-archivo="${escapar(a)}" title="${escapar(a)}">&#8206;${escapar(a)}</li>`).join("");
  ul.querySelectorAll("li").forEach((li) => {
    li.onclick = () => abrirArchivo(li.dataset.archivo);
  });
  marcarArchivoActivo();
}

function dibujarListaAbiertos() {
  const ul = $("lista-abiertos");
  App.archivos.set(App.actual, {
    contenido: codigo.value,
    guardado: App.archivos.get(App.actual)?.guardado ?? false,
  });
  ul.innerHTML = [...App.archivos.entries()].map(([n, f]) =>
    `<li data-archivo="${escapar(n)}" class="${n === App.actual ? "activo" : ""}" title="${escapar(n)}">
       &#8206;${escapar(n)}${f.guardado ? "" : ' <span class="marca-sucia">&#9679;</span>'}</li>`).join("");
  ul.querySelectorAll("li").forEach((li) => {
    li.onclick = () => abrirArchivo(li.dataset.archivo);
  });
}

function marcarArchivoActivo() {
  $("lista-archivos").querySelectorAll("li").forEach((li) =>
    li.classList.toggle("activo", li.dataset.archivo === App.actual));
}

async function guardar() {
  const nombre = $("nombre-archivo").value.trim() || "editor.nv";
  const r = await pedir("guardar", { nombre, contenido: codigo.value });
  if (r.error) { estado(r.error, "mal"); return; }
  App.actual = r.guardado;
  App.archivos.set(r.guardado, { contenido: codigo.value, guardado: true });
  $("nombre-archivo").value = r.guardado;
  $("sucio").hidden = true;
  estado("guardado en " + r.guardado, "ok");
  dibujarListaAbiertos();
  cargarListaArchivos();
}

/* ------------------------------------------------------------ compilar */

async function compilar() {
  const modo = $("modo-compilar").value;
  const optimizar = $("opt-o1").checked;
  estado("compilando...", "trabajando");
  verPanel("salida");

  const r = await pedir("compilar", {
    nombre: App.actual, contenido: codigo.value, modo, optimizar,
  });

  const caja = $("salida-texto");
  if (r.error) { caja.textContent = r.error; estado("fallo", "mal"); return; }

  const bien = r.codigo_salida === 0;
  let cabecera = `$ novac ${optimizar ? "-O1 " : ""}` +
                 `${modo === "binario" ? "" : "[" + modo + "] "}${App.actual}\n`;
  cabecera += `codigo de salida: ${r.codigo_salida}  `;
  cabecera += `tiempo de compilacion: ${r.milisegundos} ms`;
  if (r.bytes_generados) cabecera += `  binario: ${r.bytes_generados} bytes`;
  cabecera += "\n" + "-".repeat(72) + "\n";

  caja.innerHTML =
    `<span class="met">${escapar(cabecera)}</span>` +
    escapar(r.salida || "") +
    (r.errores ? `<span class="${bien ? "ok" : "mal"}">${escapar(r.errores)}</span>` : "") +
    (bien ? '<span class="ok">\ncompilacion correcta</span>' : "");

  estado(bien ? `compilado en ${r.milisegundos} ms` : "la compilacion fallo",
         bien ? "ok" : "mal");
  if (!bien) analizar();
}

/* ------------------------------------------------------------- paneles */

function verPanel(nombre) {
  document.querySelectorAll(".pestana").forEach((p) =>
    p.classList.toggle("activa", p.dataset.panel === nombre));
  document.querySelectorAll(".vista").forEach((v) =>
    v.classList.toggle("activa", v.id === "v-" + nombre));
}

/* ------------------------------------------------------------- eventos */

function conectar() {
  codigo.addEventListener("input", (e) => {
    // Al cerrar un bloque, la llave se alinea con la linea que lo abrio.
    if (e.data === "}") desangrarCierre();

    marcarSucio();
    redibujar();
    programarAnalisis();

    /*
     * Cuando se dispara el completado.
     *
     * Al escribir letras, como en cualquier editor. Y ademas despues de ':' o
     * de '->', que son las dos posiciones donde el lenguaje solo admite un
     * tipo: ahi la lista es corta y exacta, y es justo cuando mas ayuda que
     * aparezca sola. Sin esta segunda condicion el completado de tipos solo
     * salia con Ctrl+Espacio, que es tanto como no tenerlo.
     */
    const hasta = codigo.value.slice(0, codigo.selectionStart);
    const letra = /[A-Za-z_]$/.test(hasta);
    const traTipo = /(:|->)\s*$/.test(hasta);

    if (letra || traTipo) {
      clearTimeout(App.tempSug);
      App.tempSug = setTimeout(pedirSugerencias, 130);
    } else {
      cerrarPopup();
    }
  });

  codigo.addEventListener("keydown", (e) => {
    if (!popup.hidden) {
      if (e.key === "ArrowDown") { e.preventDefault(); seleccionar(App.seleccion + 1); return; }
      if (e.key === "ArrowUp")   { e.preventDefault(); seleccionar(App.seleccion - 1); return; }
      if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); aceptarSugerencia(); return; }
      if (e.key === "Escape")    { e.preventDefault(); cerrarPopup(); return; }
    }

    if (e.key === " " && e.ctrlKey) { e.preventDefault(); pedirSugerencias(); return; }

    if (e.key === "s" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); guardar(); return; }

    if (e.key === "Tab") {
      // Sangria de cuatro espacios; un tab literal rompe la alineacion de las capas.
      e.preventDefault();
      const i = codigo.selectionStart;
      codigo.value = codigo.value.slice(0, i) + "    " + codigo.value.slice(codigo.selectionEnd);
      codigo.selectionStart = codigo.selectionEnd = i + 4;
      marcarSucio(); redibujar(); programarAnalisis();
      return;
    }

    if (e.key === "Enter") {
      // Mantiene la sangria de la linea y agrega un nivel tras una llave.
      e.preventDefault();
      const i = codigo.selectionStart;
      const sangria = sangriaDeLinea(codigo.value, i);
      const previo = codigo.value.slice(0, i).trimEnd().slice(-1);
      const extra = previo === "{" ? "    " : "";
      const inserta = "\n" + sangria + extra;
      codigo.value = codigo.value.slice(0, i) + inserta + codigo.value.slice(codigo.selectionEnd);
      codigo.selectionStart = codigo.selectionEnd = i + inserta.length;
      marcarSucio(); redibujar(); programarAnalisis();
      return;
    }
  });

  // El desplazamiento de las tres capas y del gutter va siempre junto.
  lienzo.addEventListener("scroll", () => {
    gutter.scrollTop = lienzo.scrollTop;
    if (!popup.hidden) cerrarPopup();
    globo.hidden = true;
  });

  codigo.addEventListener("click", () => { dibujarGutter(codigo.value); cerrarPopup(); });
  codigo.addEventListener("keyup", (e) => {
    if (e.key.startsWith("Arrow") || e.key === "Home" || e.key === "End")
      dibujarGutter(codigo.value);
  });
  codigo.addEventListener("blur", () => setTimeout(cerrarPopup, 120));

  lienzo.addEventListener("mousemove", mostrarGlobo);
  lienzo.addEventListener("mouseleave", () => { globo.hidden = true; });

  $("btn-compilar").onclick = compilar;
  $("btn-guardar").onclick = guardar;
  $("btn-clones").onclick = buscarClones;
  $("btn-flujo").onclick = construirFlujo;
  $("btn-expandir").onclick = () => {
    document.body.classList.toggle("panel-alto");
    $("btn-expandir").textContent =
      document.body.classList.contains("panel-alto") ? "Reducir panel" : "Ampliar panel";
  };
  $("btn-recargar").onclick = cargarListaArchivos;
  $("filtro-archivos").oninput = cargarListaArchivos;
  $("nombre-archivo").onchange = (e) => {
    const nuevo = e.target.value.trim() || "editor.nv";
    const f = App.archivos.get(App.actual);
    App.archivos.delete(App.actual);
    App.actual = nuevo;
    App.archivos.set(nuevo, f || { contenido: codigo.value, guardado: false });
    dibujarListaAbiertos();
    analizar();
  };

  document.querySelectorAll(".pestana").forEach((p) => {
    p.onclick = () => verPanel(p.dataset.panel);
  });

  window.addEventListener("resize", () => { medir(); redibujar(); });
}

/* ------------------------------------------------------------- arranque */

async function arrancar() {
  medir();
  conectar();

  const info = await pedir("estado");
  if (!info.nucleo) {
    estado("falta compilar novaide", "mal");
    return;
  }

  codigo.value = EJEMPLO;
  App.archivos.set(App.actual, { contenido: EJEMPLO, guardado: false });
  redibujar();
  dibujarListaAbiertos();
  await cargarListaArchivos();
  analizar();
}

arrancar();
