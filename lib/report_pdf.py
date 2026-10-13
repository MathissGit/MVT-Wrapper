#!/usr/bin/env python3
"""Génère un rapport PDF structuré à partir de rapport.txt.

Moteur PDF minimal, python standard uniquement (aucune dépendance externe :
ni reportlab, ni pandoc, ni LibreOffice). Polices base-14 Helvetica / Courier,
encodage WinAnsi (les accents sont conservés ; les glyphes hors CP1252 sont
translittérés).

Rendu : page de titre + métadonnées, sections avec titres colorés, tableaux
clé/valeur, pastilles de sévérité, encadré de verdict et pagination.

Usage : python3 report_pdf.py <rapport.txt> <rapport.pdf>
"""
import re
import sys

# ------------------------------------------------------------------
# Géométrie (A4) et couleurs
# ------------------------------------------------------------------
PAGE_W, PAGE_H = 595.0, 842.0
ML, MR, MT, MB = 52.0, 52.0, 56.0, 58.0
CW = PAGE_W - ML - MR

DARK = (0.12, 0.14, 0.18)
GREY = (0.42, 0.45, 0.50)
SOFT = (0.60, 0.63, 0.68)
ACCENT = (0.09, 0.28, 0.52)
LINE = (0.80, 0.82, 0.86)
WHITE = (1.0, 1.0, 1.0)
RED = (0.72, 0.10, 0.12)
ORANGE = (0.83, 0.45, 0.05)
YELLOW = (0.72, 0.56, 0.00)
GREEN = (0.10, 0.52, 0.26)
BLUE = (0.16, 0.36, 0.66)

SEV_COLOR = {"CRITICAL": RED, "HIGH": ORANGE, "MEDIUM": YELLOW, "LOW": BLUE, "INFO": GREY}

# Glyphes hors CP1252 -> équivalents ASCII (les encadrés du texte source).
_TRANS = str.maketrans({
    "═": "=", "─": "-", "│": "|", "┌": "+", "┐": "+", "└": "+", "┘": "+",
    "├": "+", "┤": "+", "┬": "+", "┴": "+", "┼": "+",
    "↑": "^", "↓": "v", "≥": ">=", "✔": "+", "•": "*", "✓": "v",
    "→": "->", "…": "...",
})

# ------------------------------------------------------------------
# Largeurs de glyphes Helvetica (AFM /1000). Défaut 556 pour le reste.
# ------------------------------------------------------------------
_REG = {
    32: 278, 33: 278, 34: 355, 35: 556, 36: 556, 37: 889, 38: 667, 39: 191,
    40: 333, 41: 333, 42: 389, 43: 584, 44: 278, 45: 333, 46: 278, 47: 278,
    48: 556, 49: 556, 50: 556, 51: 556, 52: 556, 53: 556, 54: 556, 55: 556,
    56: 556, 57: 556, 58: 278, 59: 278, 60: 584, 61: 584, 62: 584, 63: 556,
    64: 1015, 65: 667, 66: 667, 67: 722, 68: 722, 69: 667, 70: 611, 71: 778,
    72: 722, 73: 278, 74: 500, 75: 667, 76: 556, 77: 833, 78: 722, 79: 778,
    80: 667, 81: 778, 82: 722, 83: 667, 84: 611, 85: 722, 86: 667, 87: 944,
    88: 667, 89: 667, 90: 611, 91: 278, 92: 278, 93: 278, 94: 469, 95: 556,
    96: 333, 97: 556, 98: 556, 99: 500, 100: 556, 101: 556, 102: 278, 103: 556,
    104: 556, 105: 222, 106: 222, 107: 500, 108: 222, 109: 833, 110: 556,
    111: 556, 112: 556, 113: 556, 114: 333, 115: 500, 116: 278, 117: 556,
    118: 500, 119: 722, 120: 500, 121: 500, 122: 500, 123: 334, 124: 260,
    125: 334, 126: 584,
}
_BOLD = {
    32: 278, 33: 333, 34: 474, 35: 556, 36: 556, 37: 889, 38: 722, 39: 238,
    40: 333, 41: 333, 42: 389, 43: 584, 44: 278, 45: 333, 46: 278, 47: 278,
    48: 556, 49: 556, 50: 556, 51: 556, 52: 556, 53: 556, 54: 556, 55: 556,
    56: 556, 57: 556, 58: 333, 59: 333, 60: 584, 61: 584, 62: 584, 63: 611,
    64: 975, 65: 722, 66: 722, 67: 722, 68: 722, 69: 667, 70: 611, 71: 778,
    72: 722, 73: 278, 74: 556, 75: 722, 76: 611, 77: 833, 78: 722, 79: 778,
    80: 667, 81: 778, 82: 722, 83: 667, 84: 611, 85: 722, 86: 667, 87: 944,
    88: 667, 89: 667, 90: 611, 91: 333, 92: 278, 93: 333, 94: 584, 95: 556,
    96: 333, 97: 556, 98: 611, 99: 556, 100: 611, 101: 556, 102: 333, 103: 611,
    104: 611, 105: 278, 106: 278, 107: 556, 108: 278, 109: 889, 110: 611,
    111: 611, 112: 611, 113: 611, 114: 389, 115: 556, 116: 333, 117: 611,
    118: 556, 119: 778, 120: 556, 121: 556, 122: 500, 123: 389, 124: 280,
    125: 389, 126: 584,
}


def width_of(s, size, bold=False, mono=False):
    if mono:
        return 0.6 * size * len(s)
    w = _BOLD if bold else _REG
    return size * sum(w.get(ord(ch), 556) for ch in s) / 1000.0


def wrap(s, size, maxw, bold=False, mono=False):
    out, cur = [], ""
    for wd in (s or "").split(" "):
        cand = wd if not cur else cur + " " + wd
        if width_of(cand, size, bold, mono) <= maxw:
            cur = cand
            continue
        if cur:
            out.append(cur)
        while width_of(wd, size, bold, mono) > maxw and len(wd) > 1:
            k = len(wd)
            while k > 1 and width_of(wd[:k], size, bold, mono) > maxw:
                k -= 1
            out.append(wd[:k])
            wd = wd[k:]
        cur = wd
    if cur or not out:
        out.append(cur)
    return out


def _tint(color, k=0.15):
    return tuple(1 - (1 - c) * k for c in color)


def _esc(s):
    """Échappe une chaîne pour un littéral PDF (parenthèses / antislash)."""
    data = (s or "").translate(_TRANS).encode("cp1252", "replace")
    return data.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)")


def _font(bold=False, mono=False, italic=False):
    if mono:
        return "F4"
    if italic:
        return "F3"
    return "F1" if bold else "F2"


class PDF:
    """Accumule les opérations de contenu, page par page."""

    def __init__(self):
        self.pages = []
        self.ops = None
        self.y = 0.0
        self.new_page()

    def new_page(self):
        if self.ops is not None:
            self.pages.append(self.ops)
        self.ops = []
        self.y = PAGE_H - MT

    def ensure(self, h):
        if self.y - h < MB:
            self.new_page()

    def text(self, x, y, s, font, size, color):
        r, g, b = color
        data = _esc(s)
        self.ops.append(b"BT /%s %g Tf %g %g %g rg 1 0 0 1 %g %g Tm (%s) Tj ET"
                        % (font.encode(), size, r, g, b, x, y, data))

    def rect(self, x, y, w, h, color):
        r, g, b = color
        self.ops.append(b"%g %g %g rg %g %g %g %g re f" % (r, g, b, x, y, w, h))

    def hline(self, x, y, w, color=LINE, lw=0.7):
        r, g, b = color
        self.ops.append(b"%g %g %g RG %g w %g %g m %g %g l S" % (r, g, b, lw, x, y, x + w, y))

    def para(self, s, size=10.0, color=DARK, bold=False, mono=False, italic=False,
             indent=0.0, leading=None, before=0.0, after=0.0):
        leading = leading or size * 1.4
        self.y -= before
        for ln in wrap(s, size, CW - indent, bold, mono):
            self.ensure(leading)
            self.y -= leading
            self.text(ML + indent, self.y + (leading - size) * 0.75, ln,
                      _font(bold, mono, italic), size, color)
        self.y -= after

    def section(self, title):
        self.ensure(48)
        self.y -= 10
        self.rect(ML, self.y - 4, 3, 18, ACCENT)
        self.text(ML + 11, self.y, title, "F1", 12.5, ACCENT)
        self.y -= 8
        self.hline(ML, self.y, CW, LINE)
        self.y -= 7

    def subhead(self, title):
        # Même famille visuelle que section() : barrette + couleur d'accent,
        # en plus léger (hiérarchie sans rupture de style).
        self.ensure(26)
        self.y -= 6
        self.rect(ML, self.y - 3, 2, 14, ACCENT)
        self.text(ML + 9, self.y - 1, title, "F1", 10.5, ACCENT)
        self.hline(ML, self.y - 9, CW, LINE, 0.5)
        self.y -= 20

    def kv(self, label, value, size=9.5, labw=140.0, vcolor=DARK):
        # Colonne libellés fixe ; un libellé trop long est replié au lieu de
        # décaler la colonne valeurs (tableaux alignés et homogènes).
        lx = ML + labw
        lab_lines = wrap(label, size, labw - 8, bold=True)
        val_lines = wrap(value, size, max(60.0, PAGE_W - MR - lx))
        n = max(len(lab_lines), len(val_lines))
        self.ensure(n * size * 1.4 + 2)
        yy = self.y
        for k in range(n):
            yy -= size * 1.4
            base = yy + (size * 1.4 - size) * 0.75
            if k < len(lab_lines):
                self.text(ML, base, lab_lines[k], "F1", size, GREY)
            if k < len(val_lines):
                self.text(lx, base, val_lines[k], "F2", size, vcolor)
        self.y = yy - 3

    def chips(self, counts):
        size, h = 9.0, 19.0
        self.ensure(h + 8)
        self.y -= 5
        x, base = ML, self.y - h
        for sev in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"):
            txt = "%s %d" % (sev, counts.get(sev, 0))
            w = width_of(txt, size, True) + 14
            self.rect(x, base, w, h, SEV_COLOR[sev])
            self.text(x + 7, base + 6.5, txt, "F1", size, WHITE)
            x += w + 6
        self.y = base - 9

    def verdict(self, text, color):
        size = 11.0
        lines = wrap(text, size, CW - 30, True)
        h = len(lines) * size * 1.4 + 16
        self.ensure(h + 10)
        self.y -= 6
        top = self.y
        self.rect(ML, top - h, CW, h, _tint(color))
        self.rect(ML, top - h, 5, h, color)
        yy = top - 8
        for ln in lines:
            yy -= size * 1.4
            self.text(ML + 16, yy + (size * 1.4 - size) * 0.75, ln, "F1", size, color)
        self.y = top - h - 8

    def detection(self, sev, msg):
        size = 9.5
        color = SEV_COLOR.get(sev, GREY)
        mcolor = DARK
        if "SPYWARE AVERE" in msg.upper():
            mcolor = RED
        elif "DOUBLE LEGITIME" in msg.upper():
            mcolor = ORANGE
        tagw = width_of(sev, 8.0, True) + 10
        lines = wrap(msg, size, CW - tagw - 8)
        self.ensure(size * 1.5 + 6)
        self.y -= size * 1.5
        self.rect(ML, self.y, tagw, 12, color)
        self.text(ML + 5, self.y + 3, sev, "F1", 8.0, WHITE)
        self.text(ML + tagw + 8, self.y + 3, lines[0], "F1", size, mcolor)
        self.y -= 2
        for ln in lines[1:]:
            self.ensure(size * 1.3)
            self.y -= size * 1.3
            self.text(ML + tagw + 8, self.y + 1, ln, "F2", size, mcolor)

    def detail(self, s, color=GREY):
        for ln in wrap(s, 8.5, CW - 46, mono=True):
            self.ensure(12)
            self.y -= 12
            self.text(ML + 30, self.y + 1, ln, "F4", 8.5, color)


# ------------------------------------------------------------------
# Analyse de rapport.txt
# ------------------------------------------------------------------
def parse(text):
    lines = text.split("\n")
    i = 0
    while i < len(lines) and not lines[i].startswith("═"):
        i += 1
    title = "RAPPORT D'ANALYSE - MVT WRAPPER"
    if i < len(lines):
        i += 1
        if i < len(lines) and lines[i].strip():
            title = lines[i].strip()
        i += 1
        if i < len(lines) and lines[i].startswith("═"):
            i += 1
    meta = []
    while i < len(lines) and not re.match(r'^-{6,}\s*$', lines[i]):
        m = re.match(r'^(.+?)\s*:\s*(.*)$', lines[i])
        if m and m.group(1).strip():
            meta.append((m.group(1).strip(), m.group(2).strip()))
        i += 1
    sections, cur, body = [], None, []
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("═"):
            break
        if re.match(r'^-{6,}\s*$', ln) and i + 1 < len(lines):
            nxt = lines[i + 1].strip()
            # Un séparateur suivi d'un autre séparateur ou d'une ligne vide
            # n'ouvre pas de section (évite les sections sans titre).
            if not nxt or re.match(r'^-{6,}\s*$', nxt):
                i += 1
                continue
            if cur is not None:
                sections.append((cur, body))
            cur = nxt
            body = []
            i += 3
            continue
        if cur is not None:
            body.append(ln)
        i += 1
    if cur is not None:
        sections.append((cur, body))
    return title, meta, sections


def _verdict_color(val):
    v = val.upper()
    if v.startswith("CRITIQUE"):
        return RED
    if v.startswith("ELEVE"):
        return ORANGE
    if v.startswith("MOYEN"):
        return YELLOW
    if v.startswith("FAIBLE"):
        return BLUE
    return GREEN


def _counts(fragment):
    out = {}
    for name, n in re.findall(r'([A-Z]+)\s*:\s*(\d+)', fragment):
        out[name] = int(n)
    return out


def _value_color(val):
    vu = val.upper()
    if "CONTRÔLER" in vu:
        return RED
    if "VERIFIEE" in vu or vu.strip().startswith("OK"):
        return GREEN
    return DARK


def _is_kv_line(s):
    if ":" not in s:
        return False
    label = s.split(":", 1)[0].strip()
    return 2 <= len(label) <= 46


def render_body(pdf, title, body):
    kv_section = title.upper().startswith(("IDENTIFICATION", "PREUVES"))
    modules_section = title.upper().startswith("MODULES")
    for raw in body:
        if not raw.strip():
            pdf.y -= 6
            continue
        s = raw.strip()
        # Détections numérotées : pastille de sévérité + message.
        m = re.match(r'^\d+\)\s*\[(\w+)\]\s*(.*)$', s)
        if m:
            pdf.detection(m.group(1).upper(), m.group(2))
            continue
        # Sous-section (nom de module entre crochets).
        if re.match(r'^\[[\w.\-]+\]$', s):
            pdf.subhead(s)
            continue
        if s.startswith("IoC :"):
            pdf.detail(s, RED if "SPYWARE" in s.upper() else GREY)
            continue
        if s.startswith("Détails :"):
            pdf.detail(s, SOFT)
            continue
        if s.startswith("Verdict") and ":" in s:
            val = s.split(":", 1)[1].strip()
            pdf.verdict(val, _verdict_color(val))
            continue
        if s.startswith("Répartition séverite") and ":" in s:
            pdf.para("Répartition par sévérité", size=9.5, bold=True, color=GREY, after=3)
            pdf.chips(_counts(s.split(":", 1)[1]))
            continue
        # Lignes de synthèse (indentées dans le texte source) : tableau aligné.
        if re.match(r'^(Détections|dont spyware avérés|Modules concernés)\b', s) and ":" in s:
            label, val = s.split(":", 1)
            pdf.kv(label.strip() + " :", val.strip(), vcolor=_value_color(val.strip()))
            continue
        # Liste simple (modules exécutés) : puce + retrait, style uniforme.
        if modules_section and ":" not in s:
            pdf.para("* " + s, size=9.5, indent=14, after=2)
            continue
        # Tableau clé/valeur : même style dans toutes les sections. Les lignes
        # indentées ne deviennent un tableau que dans les sections structurées
        # (IDENTIFICATION, PREUVES) ; ailleurs, elles restent du texte.
        indented = raw.startswith((" ", "\t"))
        if _is_kv_line(s) and (kv_section or not indented):
            label, val = s.split(":", 1)
            pdf.kv(label.strip() + " :", val.strip(), vcolor=_value_color(val.strip()))
            continue
        if s.startswith("* "):
            pdf.para(s[2:], size=9.5, italic=True, color=GREY, indent=14, after=2)
            continue
        pdf.para(s, size=10.0, indent=12 if indented else 0, after=2)


def render(pdf, title, meta, sections):
    pdf.y -= 8
    pdf.text(ML, pdf.y - 22, "MVT-WRAPPER", "F1", 13, ACCENT)
    pdf.y -= 34
    pdf.hline(ML, pdf.y, CW, ACCENT, 1.2)
    pdf.y -= 2
    pdf.para(title, size=19, bold=True, color=DARK, leading=25, before=8, after=4)
    pdf.para("Élément technique d'aide à l'orientation — non expertise judiciaire.",
             size=9.5, color=GREY, after=12)
    for label, value in meta:
        pdf.kv(label + " :", value)
    pdf.y -= 4
    for stitle, body in sections:
        pdf.section(stitle)
        render_body(pdf, stitle, body)


# ------------------------------------------------------------------
# Assemblage PDF (objets, polices, pagination)
# ------------------------------------------------------------------
def _decor(page_num, total, case_id):
    ops = []
    ops.append(b"BT /F1 8 Tf 0.09 0.28 0.52 rg 1 0 0 1 %g %g Tm (RAPPORT D'ANALYSE) Tj ET"
               % (ML, PAGE_H - 38))
    if case_id:
        w = width_of(case_id, 8, True)
        ops.append(b"BT /F1 8 Tf 0.42 0.45 0.5 rg 1 0 0 1 %g %g Tm (%s) Tj ET"
                   % (PAGE_W - MR - w, PAGE_H - 38, _esc(case_id)))
    ops.append(b"0.8 0.82 0.86 RG 0.6 w %g %g m %g %g l S" % (ML, PAGE_H - 44, PAGE_W - MR, PAGE_H - 44))
    ops.append(b"0.8 0.82 0.86 RG 0.6 w %g %g m %g %g l S" % (ML, MB - 16, PAGE_W - MR, MB - 16))
    ops.append(b"BT /F2 8 Tf 0.42 0.45 0.5 rg 1 0 0 1 %g %g Tm (MVT-Wrapper) Tj ET"
               % (ML, MB - 28))
    ptxt = "page %d/%d" % (page_num, total)
    w = width_of(ptxt, 8, True)
    ops.append(b"BT /F1 8 Tf 0.42 0.45 0.5 rg 1 0 0 1 %g %g Tm (%s) Tj ET"
               % (PAGE_W - MR - w, MB - 28, ptxt.encode()))
    return b"\n".join(ops) + b"\n"


def build(pdf, case_id):
    pages = pdf.pages or [[]]
    total = len(pages)
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        None,  # 2 : Pages (rempli plus bas)
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
    ]
    kids = []
    for idx, ops in enumerate(pages):
        page_obj = 7 + 2 * idx
        cont_obj = 8 + 2 * idx
        kids.append(b"%d 0 R" % page_obj)
        content = _decor(idx + 1, total, case_id) + b"\n".join(ops) + b"\n"
        objs.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %g %g] "
                    b"/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R /F4 6 0 R >> >> "
                    b"/Contents %d 0 R >>" % (PAGE_W, PAGE_H, cont_obj))
        objs.append(b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream")
    objs[1] = b"<< /Type /Pages /Kids [" + b" ".join(kids) + b"] /Count %d >>" % total

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for num, o in enumerate(objs, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % num + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for off in offsets[1:]:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return bytes(out)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: report_pdf.py <rapport.txt> <rapport.pdf>\n")
        return 2
    txt, pdf_path = sys.argv[1], sys.argv[2]
    with open(txt, encoding="utf-8") as fh:
        text = fh.read()
    title, meta, sections = parse(text)
    case_id = ""
    for label, value in meta:
        if label.lower().startswith("affaire"):
            case_id = value
            break
    pdf = PDF()
    render(pdf, title, meta, sections)
    if pdf.ops is not None:
        pdf.pages.append(pdf.ops)
        pdf.ops = None
    data = build(pdf, case_id)
    with open(pdf_path, "wb") as fh:
        fh.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
