#!/usr/bin/env python3
"""Renderiza el AST de Nova como un diagrama SVG coloreado, sin dependencias."""

import argparse
import html
import re
import subprocess
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path


MAX_NODE_WIDTH = 310
CHAR_WIDTH = 7.1
NODE_PADDING = 30
HORIZONTAL_GAP = 42
VERTICAL_GAP = 48
NODE_RADIUS = 10


@dataclass
class Node:
    label: str
    kind: str
    children: list["Node"] = field(default_factory=list)
    x: float = 0
    y: float = 0
    width: float = 0
    height: float = 0
    lines: list[str] = field(default_factory=list)


PALETTE = {
    "Programa": ("#DCEAFE", "#2563EB"),
    "Imports": ("#EDE9FE", "#7C3AED"),
    "Globales": ("#EDE9FE", "#7C3AED"),
    "Funcion": ("#DBEAFE", "#1D4ED8"),
    "Parametros": ("#E0F2FE", "#0284C7"),
    "Parametro": ("#E0F2FE", "#0284C7"),
    "Bloque": ("#DCFCE7", "#16A34A"),
    "Variable": ("#D1FAE5", "#059669"),
    "Constante": ("#FEF3C7", "#D97706"),
    "Tipo": ("#F3E8FF", "#9333EA"),
    "Asignacion": ("#FFEDD5", "#EA580C"),
    "Si": ("#FCE7F3", "#DB2777"),
    "Dum": ("#FCE7F3", "#DB2777"),
    "Per": ("#FCE7F3", "#DB2777"),
    "Llamada": ("#CFFAFE", "#0891B2"),
    "Ident": ("#F1F5F9", "#475569"),
    "Entero": ("#FEF9C3", "#CA8A04"),
    "Cadena": ("#FCE7F3", "#BE185D"),
    "Booleano": ("#FEF9C3", "#CA8A04"),
}


def parse_ast(text):
    stack: list[tuple[int, Node]] = []
    root = None
    node_count = 0
    for raw in text.splitlines():
        if not raw.strip() or raw.startswith("==="):
            continue
        # El arbol de novac -t viene con conectores. Cada nivel ocupa cuatro
        # columnas, asi que la cantidad de caracteres del prefijo sigue
        # sirviendo como profundidad.
        content = raw.lstrip(" │├└─")
        indent = len(raw) - len(content)
        content = content.strip()
        match = re.match(r"([A-Za-z]+)(?:\s+(.*?))?\s+\(linea\s+\d+,\s*columna\s+\d+\)$", content)
        if not match:
            raise ValueError(f"formato de AST no reconocido: {content}")
        kind, suffix = match.groups()
        label = kind + (f" {suffix}" if suffix else "")
        label = label.replace("\\n", " ").replace("\\t", " ")
        node = Node(label, kind)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if stack and indent <= stack[-1][0]:
            raise ValueError("indentación inválida en el AST")
        if stack:
            stack[-1][1].children.append(node)
        elif root is None:
            root = node
        else:
            raise ValueError("el AST contiene más de una raíz")
        stack.append((indent, node))
        node_count += 1
    if root is None:
        raise ValueError("el AST está vacío")
    if root.kind != "Programa":
        raise ValueError(f"la raíz del AST debe ser Programa, no {root.kind}")
    if node_count < 2:
        raise ValueError("el AST no contiene una estructura de programa")
    return root


def measure(node):
    max_chars = int((MAX_NODE_WIDTH - NODE_PADDING) / CHAR_WIDTH)
    node.lines = []
    for paragraph in node.label.splitlines() or [node.label]:
        node.lines.extend(textwrap.wrap(
            paragraph,
            width=max_chars,
            break_long_words=True,
            break_on_hyphens=False,
        ) or [""])
    node.width = min(
        MAX_NODE_WIDTH,
        max(142, max(len(line) for line in node.lines) * CHAR_WIDTH + NODE_PADDING),
    )
    node.height = max(42, len(node.lines) * 17 + 18)
    for child in node.children:
        measure(child)


def shift_subtree(node, amount):
    node.x += amount
    for child in node.children:
        shift_subtree(child, amount)


def layout(node):
    half = node.width / 2
    if not node.children:
        node.x = 0
        return [(-half, half)]

    contours = []
    placed_children = []
    for child in node.children:
        child_contours = layout(child)
        shift = 0
        for depth, (left, _) in enumerate(child_contours):
            if depth < len(contours):
                shift = max(
                    shift,
                    contours[depth][1] + HORIZONTAL_GAP - left,
                )
        shift_subtree(child, shift)
        placed_children.append((child, child_contours, shift))
        for depth, (left, right) in enumerate(child_contours):
            shifted = (left + shift, right + shift)
            if depth == len(contours):
                contours.append(shifted)
            else:
                contours[depth] = (
                    min(contours[depth][0], shifted[0]),
                    max(contours[depth][1], shifted[1]),
                )

    center = (placed_children[0][0].x + placed_children[-1][0].x) / 2
    for child, _, _ in placed_children:
        shift_subtree(child, -center)
    node.x = 0
    return [(-half, half)] + [(left - center, right - center) for left, right in contours]


def place_levels(root):
    levels = []

    def collect(node, depth):
        while depth >= len(levels):
            levels.append(0)
        levels[depth] = max(levels[depth], node.height)
        for child in node.children:
            collect(child, depth + 1)

    collect(root, 0)
    y_positions = [56 + levels[0] / 2]
    for depth in range(1, len(levels)):
        y_positions.append(
            y_positions[-1] + levels[depth - 1] / 2
            + VERTICAL_GAP + levels[depth] / 2
        )

    def assign(node, depth):
        node.y = y_positions[depth]
        for child in node.children:
            assign(child, depth + 1)

    assign(root, 0)


def emit_node(node, out):
    fill, stroke = PALETTE.get(node.kind, ("#F8FAFC", "#64748B"))
    half = node.width / 2
    out.append(
        f'<g class="node" transform="translate({node.x:.1f},{node.y:.1f})">'
        f'<title>{html.escape(node.label)}</title>'
        f'<rect x="-{half:.1f}" y="{-node.height / 2:.1f}" '
        f'width="{node.width:.1f}" height="{node.height:.1f}" '
        f'rx="{NODE_RADIUS}" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>'
    )
    line_height = 17
    first_y = -((len(node.lines) - 1) * line_height) / 2
    out.append(
        '<text text-anchor="middle" dominant-baseline="central">'
        + "".join(
            f'<tspan x="0" y="{first_y + index * line_height:.1f}">'
            f'{html.escape(line)}</tspan>'
            for index, line in enumerate(node.lines)
        )
        + "</text></g>"
    )
    for child in node.children:
        emit_node(child, out)


def emit_edges(node, out):
    for child in node.children:
        start_y = node.y + node.height / 2
        end_y = child.y - child.height / 2
        mid_y = (start_y + end_y) / 2
        out.append(
            f'<path d="M {node.x:.1f} {start_y:.1f} '
            f'V {mid_y:.1f} H {child.x:.1f} V {end_y:.1f}" '
            'fill="none" stroke="#64748B" stroke-width="1.5" '
            'stroke-linecap="round" stroke-linejoin="round"/>'
        )
        emit_edges(child, out)


def render(root, source, output):
    measure(root)
    layout(root)
    place_levels(root)
    nodes = list(walk(root))
    min_x = min(node.x - node.width / 2 for node in nodes)
    max_x = max(node.x + node.width / 2 for node in nodes)
    margin = 48
    width = max(680, int(max_x - min_x + 2 * margin))
    height = int(max(node.y + node.height / 2 for node in nodes) + 54)
    x_offset = margin - min_x
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img">',
        "<title>Árbol sintáctico Nova</title>",
        "<style>text{font:12px system-ui,sans-serif;fill:#172033}"
        ".node{filter:drop-shadow(0 2px 2px #0f172a18)}</style>",
        f'<rect width="{width}" height="{height}" fill="#F8FAFC"/>',
        f'<text x="24" y="30" font-family="system-ui,sans-serif" font-size="18" '
        f'font-weight="700" fill="#0F172A">Árbol sintáctico — {html.escape(source)}</text>',
        f'<g transform="translate({x_offset:.1f},0)">',
    ]
    emit_edges(root, out)
    emit_node(root, out)
    out.extend(["</g>", "</svg>"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(out) + "\n", encoding="utf-8")


def max_depth(node):
    if not node.children:
        return 0
    return 1 + max(max_depth(child) for child in node.children)


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--novac", type=Path, required=True, help="ejecutable del compilador")
    parser.add_argument("--source", type=Path, required=True, help="archivo fuente .nv")
    parser.add_argument("--output", type=Path, required=True, help="destino .svg")
    args = parser.parse_args()
    try:
        result = subprocess.run(
            [str(args.novac.resolve()), "-t", str(args.source)],
            check=False, capture_output=True, text=True,
        )
        if result.returncode:
            sys.stderr.write(result.stderr)
            sys.stderr.write(result.stdout)
            return result.returncode
        root = parse_ast(result.stdout)
        render(root, str(args.source), args.output)
    except (OSError, ValueError) as exc:
        print(f"arbol_svg: {exc}", file=sys.stderr)
        return 1
    print(f"AST SVG: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
