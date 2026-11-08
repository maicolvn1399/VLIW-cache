#!/usr/bin/env python3
"""
Servidor de la interfaz del IDE de Nova.

La division de responsabilidades que pide el proyecto es estricta: toda la
logica que entiende el lenguaje esta en C, dentro de 'novaide', y este
servidor no sabe nada de Nova. Lo unico que hace es recibir lo que el editor
del navegador tiene en pantalla, pasarselo a 'novaide' y devolver su
respuesta tal cual. Si algo del analisis hay que cambiarlo, se cambia en C;
aqui no hay reglas del lenguaje que puedan quedar desincronizadas.

Cada peticion escribe el contenido del editor en un archivo temporal y lanza
'novaide' sobre el. Eso permite analizar lo que el usuario esta escribiendo
sin obligarlo a guardar, y mantiene al nucleo trabajando siempre sobre un
archivo real, igual que el compilador.

Uso:
    python3 ide/servidor.py [--puerto 8099] [--raiz .]
"""

import argparse
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import webbrowser

AQUI = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(AQUI, "web")

# Limite de tiempo por invocacion. El analisis de un archivo normal tarda
# milisegundos; este tope solo existe para que un caso patologico no deje la
# interfaz colgada esperando.
TIEMPO_LIMITE = 20


class Nucleo:
    """Envoltura de los binarios en C."""

    def __init__(self, raiz):
        self.raiz = os.path.abspath(raiz)
        self.novaide = os.path.join(self.raiz, "novaide")
        self.novac = os.path.join(self.raiz, "novac")

    def disponible(self):
        return os.path.isfile(self.novaide) and os.access(self.novaide, os.X_OK)

    def ejecutar(self, argumentos):
        """Corre novaide y devuelve su JSON ya interpretado."""
        try:
            r = subprocess.run(
                [self.novaide] + argumentos,
                capture_output=True, text=True,
                timeout=TIEMPO_LIMITE, cwd=self.raiz,
            )
        except subprocess.TimeoutExpired:
            return {"error": "el analisis excedio el tiempo limite"}
        except OSError as e:
            return {"error": f"no se pudo ejecutar novaide: {e}"}

        if not r.stdout.strip():
            return {"error": "novaide no produjo salida", "stderr": r.stderr[-2000:]}
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError as e:
            return {"error": f"respuesta de novaide ilegible: {e}",
                    "crudo": r.stdout[:2000]}

    def compilar(self, ruta, modo, optimizar=False):
        """
        Corre el compilador de verdad sobre el archivo. Es lo que hace el boton
        de compilar: el IDE no simula la compilacion, la ejecuta.

        'optimizar' agrega -O1, que enciende la fase 6. Vale para todos los
        modos a proposito: asi se puede mirar el mismo archivo con y sin
        optimizar en cualquiera de las vistas -- el codigo intermedio, el
        ensamblador, los bundles -- y comparar.
        """
        banderas = {
            "binario": [],
            "tokens": ["--tokens"],
            "ast": ["-t"],
            "simbolos": ["--sym"],
            "ir": ["--ir"],
            "vivacidad": ["--vivacidad"],
            "metricas": ["--metricas"],
            "ensamblador": ["-s"],
            "paquetes": ["-p"],
        }.get(modo, [])

        if optimizar:
            banderas = banderas + ["-O1"]

        salida = None
        argumentos = [self.novac] + banderas + [ruta]

        # Ojo con -o: varias banderas de inspeccion lo interpretan como "manda
        # el reporte a ese archivo" en vez de a la pantalla. '-p' es una de
        # ellas, asi que pasarle -o dejaba el panel de Salida en blanco con el
        # listado de bundles escondido en un archivo. Solo lo reciben los modos
        # que de verdad producen un binario.
        # --metricas necesita que se genere el binario para poder contar los
        # bundles, pero su reporte sale por pantalla, asi que tambien lleva -o.
        if modo in ("binario", "ensamblador", "metricas"):
            salida = ruta + ".nvx"
            argumentos += ["-o", salida]

        inicio = time.perf_counter()
        try:
            r = subprocess.run(argumentos, capture_output=True, text=True,
                               timeout=TIEMPO_LIMITE, cwd=self.raiz)
        except subprocess.TimeoutExpired:
            return {"error": "la compilacion excedio el tiempo limite"}
        except OSError as e:
            return {"error": f"no se pudo ejecutar novac: {e}"}
        transcurrido = time.perf_counter() - inicio

        tamano = None
        if salida and os.path.isfile(salida):
            tamano = os.path.getsize(salida)
            try:
                os.remove(salida)
                for extra in (".asm",):
                    otro = os.path.splitext(salida)[0] + extra
                    if os.path.isfile(otro):
                        os.remove(otro)
            except OSError:
                pass

        return {
            "modo": modo,
            "codigo_salida": r.returncode,
            "salida": r.stdout,
            "errores": r.stderr,
            # El tiempo de compilacion es una de las metricas que el proyecto
            # pide registrar; se mide aqui para poder graficarla despues.
            "milisegundos": round(transcurrido * 1000, 2),
            "bytes_generados": tamano,
        }


class Taller:
    """Archivos temporales donde se materializa el buffer del editor."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="nova_ide_")

    def escribir(self, nombre, contenido):
        base = os.path.basename(nombre or "sin_titulo.nv")
        if not base.endswith((".nv", ".nvo")):
            base += ".nv"
        ruta = os.path.join(self.dir, base)
        with open(ruta, "w", encoding="utf-8") as f:
            f.write(contenido)
        return ruta

    def limpiar(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class Manejador(http.server.SimpleHTTPRequestHandler):
    nucleo = None
    taller = None
    raiz_proyecto = None

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=WEB, **kw)

    # El log por omision ensucia la terminal con una linea por recurso.
    def log_message(self, formato, *args):
        pass

    # ------------------------------------------------------------ utiles

    def responder_json(self, datos, estado=200):
        cuerpo = json.dumps(datos, ensure_ascii=False).encode("utf-8")
        self.send_response(estado)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(cuerpo)

    def leer_peticion(self):
        largo = int(self.headers.get("Content-Length", 0))
        if largo <= 0:
            return {}
        if largo > 20 * 1024 * 1024:
            return {}
        return json.loads(self.rfile.read(largo).decode("utf-8"))

    def ruta_segura(self, relativa):
        """
        Impide salir del arbol del proyecto. El servidor escucha solo en
        localhost, pero una interfaz que lee archivos por nombre no deberia
        poder alcanzar cualquier cosa del disco ni por error.
        """
        destino = os.path.abspath(os.path.join(self.raiz_proyecto, relativa))
        if not destino.startswith(self.raiz_proyecto + os.sep):
            return None
        return destino

    # ------------------------------------------------------------- GET

    def do_GET(self):
        if self.path.startswith("/api/"):
            if self.path == "/api/estado":
                return self.responder_json({
                    "nucleo": self.nucleo.disponible(),
                    "raiz": self.raiz_proyecto,
                    "novaide": self.nucleo.novaide,
                })
            if self.path == "/api/catalogo":
                return self.responder_json(self.nucleo.ejecutar(["catalogo"]))
            if self.path == "/api/archivos":
                return self.responder_json({"archivos": self.listar_fuentes()})
            if self.path.startswith("/api/archivo?"):
                relativa = urllib.parse.unquote(self.path.split("ruta=", 1)[-1])
                destino = self.ruta_segura(relativa)
                if destino is None or not os.path.isfile(destino):
                    return self.responder_json({"error": "archivo no encontrado"}, 404)
                with open(destino, encoding="utf-8", errors="replace") as f:
                    return self.responder_json({"nombre": relativa, "contenido": f.read()})
            return self.responder_json({"error": "ruta desconocida"}, 404)
        return super().do_GET()

    def listar_fuentes(self):
        """Todos los .nv del proyecto, para el panel de archivos."""
        encontrados = []
        omitir = {".git", "ARQUITECTURA", "__pycache__", "entregables"}
        for base, dirs, archivos in os.walk(self.raiz_proyecto):
            dirs[:] = [d for d in dirs if d not in omitir and not d.startswith(".")]
            for a in archivos:
                if a.endswith(".nv"):
                    completo = os.path.join(base, a)
                    encontrados.append(os.path.relpath(completo, self.raiz_proyecto))
            if len(encontrados) > 500:
                break
        return sorted(encontrados)

    # ------------------------------------------------------------ POST

    def do_POST(self):
        if not self.path.startswith("/api/"):
            return self.responder_json({"error": "ruta desconocida"}, 404)
        try:
            peticion = self.leer_peticion()
        except (ValueError, UnicodeDecodeError) as e:
            return self.responder_json({"error": f"peticion ilegible: {e}"}, 400)

        accion = self.path[len("/api/"):]
        try:
            if accion == "diagnosticar":
                return self.responder_json(self.hacer_diagnosticar(peticion))
            if accion == "completar":
                return self.responder_json(self.hacer_completar(peticion))
            if accion == "arreglar":
                return self.responder_json(self.hacer_arreglar(peticion))
            if accion == "bloques":
                return self.responder_json(self.hacer_bloques(peticion))
            if accion == "clones":
                return self.responder_json(self.hacer_clones(peticion))
            if accion == "compilar":
                return self.responder_json(self.hacer_compilar(peticion))
            if accion == "guardar":
                return self.responder_json(self.hacer_guardar(peticion))
        except Exception as e:                       # noqa: BLE001
            return self.responder_json({"error": f"{type(e).__name__}: {e}"}, 500)
        return self.responder_json({"error": "accion desconocida"}, 404)

    def hacer_diagnosticar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar(["diagnosticar", ruta, "--con-tokens", "--como", nombre])

    def hacer_completar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar([
            "completar", ruta,
            "--linea", str(int(p.get("linea", 1))),
            "--columna", str(int(p.get("columna", 1))),
            "--como", nombre,
        ])

    def hacer_arreglar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar(["arreglar", ruta, "--como", nombre])

    def hacer_bloques(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.ejecutar(["bloques", ruta, "--como", nombre])

    def hacer_clones(self, p):
        """
        Los clones se buscan entre varios archivos a la vez: los abiertos en el
        editor, con su contenido actual, mas los que el usuario haya marcado
        del proyecto.
        """
        rutas, mostrar = [], {}
        for archivo in p.get("archivos", [])[:64]:
            nombre = archivo.get("nombre", "sin_titulo.nv")
            ruta = self.taller.escribir(nombre, archivo.get("contenido", ""))
            rutas.append(ruta)
            mostrar[ruta] = nombre

        if len(rutas) < 1:
            return {"error": "no hay archivos que comparar"}

        argumentos = ["clones"] + rutas
        argumentos += ["--min-tokens", str(int(p.get("min_tokens", 20)))]
        argumentos += ["--umbral", str(float(p.get("umbral", 0.80)))]
        resultado = self.nucleo.ejecutar(argumentos)

        # Devolver los nombres que el usuario reconoce, no los temporales.
        def nombrar(r):
            return mostrar.get(r, os.path.basename(r))

        if "archivos" in resultado:
            resultado["archivos"] = [nombrar(r) for r in resultado["archivos"]]
        for c in resultado.get("clones", []):
            for lado in ("a", "b"):
                c[lado]["archivo"] = nombrar(c[lado]["archivo"])
        return resultado

    def hacer_compilar(self, p):
        nombre = p.get("nombre", "editor.nv")
        ruta = self.taller.escribir(nombre, p.get("contenido", ""))
        return self.nucleo.compilar(ruta, p.get("modo", "binario"),
                                    bool(p.get("optimizar", False)))

    def hacer_guardar(self, p):
        destino = self.ruta_segura(p.get("nombre", ""))
        if destino is None:
            return {"error": "ruta fuera del proyecto"}
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        with open(destino, "w", encoding="utf-8") as f:
            f.write(p.get("contenido", ""))
        return {"guardado": os.path.relpath(destino, self.raiz_proyecto)}


class Servidor(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def abrir_navegador(direccion):
    """
    Abre la interfaz en el navegador.

    Bajo WSL no hay navegador dentro de Linux: el que importa es el de
    Windows. webbrowser.open() intenta 'gio open', que no existe ahi, y lo
    unico que logra es imprimir un error en la terminal justo cuando el
    servidor acaba de arrancar bien. Por eso en WSL se prueban primero las dos
    formas que si funcionan, y en cualquier caso el fallo es silencioso: la
    direccion ya quedo impresa arriba y abrirla a mano siempre sirve.
    """
    es_wsl = False
    try:
        with open("/proc/version", encoding="utf-8", errors="replace") as f:
            es_wsl = "microsoft" in f.read().lower()
    except OSError:
        pass

    if es_wsl:
        for orden in (["wslview", direccion],
                      ["cmd.exe", "/c", "start", "", direccion]):
            try:
                subprocess.run(orden, check=True, timeout=10,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except (OSError, subprocess.SubprocessError):
                continue
        return

    try:
        webbrowser.open(direccion)
    except Exception:                                # noqa: BLE001
        pass


def main():
    ap = argparse.ArgumentParser(description="Interfaz del IDE de Nova")
    ap.add_argument("--puerto", type=int, default=8099)
    ap.add_argument("--raiz", default=os.path.dirname(AQUI),
                    help="raiz del proyecto, donde estan novac y novaide")
    ap.add_argument("--sin-navegador", action="store_true")
    args = ap.parse_args()

    raiz = os.path.abspath(args.raiz)
    nucleo = Nucleo(raiz)
    if not nucleo.disponible():
        print(f"No se encontro '{nucleo.novaide}'.", file=sys.stderr)
        print("Compile primero el nucleo del IDE con:  make novaide", file=sys.stderr)
        return 1

    Manejador.nucleo = nucleo
    Manejador.taller = Taller()
    Manejador.raiz_proyecto = raiz

    direccion = f"http://127.0.0.1:{args.puerto}/"
    print("IDE de Nova")
    print(f"  proyecto : {raiz}")
    print(f"  nucleo   : {nucleo.novaide}")
    print(f"  interfaz : {direccion}")
    print("  (Ctrl+C para detener)")

    if not args.sin_navegador:
        threading.Timer(0.6, lambda: abrir_navegador(direccion)).start()

    try:
        with Servidor(("127.0.0.1", args.puerto), Manejador) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nDetenido.")
    finally:
        Manejador.taller.limpiar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
