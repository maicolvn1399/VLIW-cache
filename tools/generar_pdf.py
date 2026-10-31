#!/usr/bin/env python3
"""Render especificacion_nova.md a PDF con tipografia Unicode embebida."""

import html
import re
import sys
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    HRFlowable,
    ListFlowable,
    ListItem,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
)


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DOCS = PROJECT_ROOT / "documentacion"
SOURCE = DOCS / "especificacion_nova.md"
OUTPUT = Path(sys.argv[1]) if len(sys.argv) > 1 else DOCS / "especificacion_nova.pdf"
FONT_DIR = Path("/usr/share/fonts/truetype/dejavu")


def inline_markup(text):
    links = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
    text = links.sub(lambda m: m.group(1), text)
    text = html.escape(text)
    text = re.sub(
        r"`([^`]+)`",
        r'<font name="NovaMono" backColor="#EEF1F5">\1</font>',
        text,
    )
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", text)
    return text


def build_styles():
    pdfmetrics.registerFont(TTFont("NovaSans", str(FONT_DIR / "DejaVuSans.ttf")))
    pdfmetrics.registerFont(
        TTFont("NovaSans-Bold", str(FONT_DIR / "DejaVuSans-Bold.ttf"))
    )
    pdfmetrics.registerFont(
        TTFont("NovaMono", str(FONT_DIR / "DejaVuSansMono.ttf"))
    )
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "NovaTitle", parent=base["Title"], fontName="NovaSans-Bold",
            fontSize=23, leading=29, textColor=colors.HexColor("#17365D"),
            alignment=TA_CENTER, spaceAfter=14,
        ),
        "subtitle": ParagraphStyle(
            "NovaSubtitle", parent=base["Heading2"], fontName="NovaSans",
            fontSize=13, leading=18, textColor=colors.HexColor("#375A7F"),
            alignment=TA_CENTER, spaceAfter=12,
        ),
        "h2": ParagraphStyle(
            "NovaH2", parent=base["Heading1"], fontName="NovaSans-Bold",
            fontSize=15, leading=20, textColor=colors.HexColor("#17365D"),
            spaceBefore=12, spaceAfter=7, keepWithNext=True,
        ),
        "h3": ParagraphStyle(
            "NovaH3", parent=base["Heading2"], fontName="NovaSans-Bold",
            fontSize=11.5, leading=15, textColor=colors.HexColor("#2E5D83"),
            spaceBefore=8, spaceAfter=4, keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "NovaBody", parent=base["BodyText"], fontName="NovaSans",
            fontSize=9.3, leading=13.4, alignment=TA_JUSTIFY,
            spaceAfter=6, allowWidows=0, allowOrphans=0,
        ),
        "bullet": ParagraphStyle(
            "NovaBullet", parent=base["BodyText"], fontName="NovaSans",
            fontSize=9.1, leading=12.8, spaceAfter=2,
        ),
        "code": ParagraphStyle(
            "NovaCode", fontName="NovaMono", fontSize=7.4, leading=10,
            leftIndent=7, rightIndent=7, backColor=colors.HexColor("#F3F5F7"),
            borderColor=colors.HexColor("#D6DCE5"), borderWidth=0.4,
            borderPadding=6, spaceBefore=3, spaceAfter=8,
        ),
    }


def parse_markdown(text, styles):
    lines = text.splitlines()
    story = []
    paragraph = []
    i = 0

    def flush_paragraph():
        if paragraph:
            value = " ".join(part.strip() for part in paragraph)
            story.append(Paragraph(inline_markup(value), styles["body"]))
            paragraph.clear()

    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            flush_paragraph()
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code.append(lines[i])
                i += 1
            story.append(Preformatted("\n".join(code), styles["code"]))
            i += 1
            continue
        if not line.strip():
            flush_paragraph()
            i += 1
            continue
        if line.strip() == "---":
            flush_paragraph()
            story.extend([Spacer(1, 3), HRFlowable(width="100%", color=colors.HexColor("#9BAFC4")), Spacer(1, 7)])
            i += 1
            continue
        heading = re.match(r"^(#{1,3})\s+(.*)$", line)
        if heading:
            flush_paragraph()
            level = len(heading.group(1))
            style = styles["title"] if level == 1 else styles["h2"] if level == 2 else styles["h3"]
            story.append(Paragraph(inline_markup(heading.group(2)), style))
            i += 1
            continue
        if line.startswith("- "):
            flush_paragraph()
            items = []
            while i < len(lines) and lines[i].startswith("- "):
                items.append(
                    ListItem(
                        Paragraph(inline_markup(lines[i][2:]), styles["bullet"]),
                        bulletColor=colors.HexColor("#375A7F"),
                    )
                )
                i += 1
            story.append(
                ListFlowable(
                    items, bulletType="bullet", start="circle",
                    leftIndent=16, bulletFontName="NovaSans", bulletFontSize=6,
                    spaceAfter=6,
                )
            )
            continue
        paragraph.append(line)
        i += 1
    flush_paragraph()
    return story


def page_chrome(canvas, document):
    canvas.saveState()
    width, height = A4
    canvas.setFont("NovaSans", 7.5)
    canvas.setFillColor(colors.HexColor("#5B6573"))
    canvas.drawString(20 * mm, height - 12 * mm, "NOVA COMPILER  /  CE 1108")
    canvas.drawRightString(width - 20 * mm, 10 * mm, f"Página {document.page}")
    canvas.setStrokeColor(colors.HexColor("#CBD3DD"))
    canvas.setLineWidth(0.5)
    canvas.line(20 * mm, height - 14 * mm, width - 20 * mm, height - 14 * mm)
    canvas.restoreState()


def main():
    styles = build_styles()
    story = parse_markdown(SOURCE.read_text(encoding="utf-8"), styles)
    doc = SimpleDocTemplate(
        str(OUTPUT), pagesize=A4, rightMargin=20 * mm, leftMargin=20 * mm,
        topMargin=22 * mm, bottomMargin=18 * mm,
        title="Nova Compiler para CERBERO — Especificación técnica",
        author="Proyecto Nova Compiler / CERBERO",
    )
    doc.build(story, onFirstPage=page_chrome, onLaterPages=page_chrome)
    print(f"PDF generado: {OUTPUT}")


if __name__ == "__main__":
    main()
