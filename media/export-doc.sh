#!/usr/bin/env bash
# Export docs/OPENHUMAN-ON-OCI.md to Word and PDF. The ASCII figure is rendered
# to a PNG so it survives page width; code blocks and margins are tightened.
# Usage: media/export-doc.sh [out-dir]   (default: ~/Documents/openhuman-oci)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Documents/openhuman-oci}"; mkdir -p "$OUT"
SRC=docs/OPENHUMAN-ON-OCI.md
TMP="$(mktemp -d)"
python3 - "$SRC" "$TMP/doc.md" media/figure1-architecture.png <<'PY'
import re, sys
from PIL import Image, ImageDraw, ImageFont
src, dst, png = sys.argv[1:4]
text = open(src).read()
m = re.search(r"\n```\n(.*?)\n```\n\n\*Figure 1\.", text, re.S)
art = m.group(1)
# Render the ASCII figure as an image.
lines = art.splitlines()
font = None
for cand in ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf", "/Library/Fonts/Courier New.ttf"]:
    try:
        font = ImageFont.truetype(cand, 15); break
    except OSError:
        pass
font = font or ImageFont.load_default()
cw = font.getbbox("M")[2]; lh = 19
W = cw * max(len(l) for l in lines) + 40; H = lh * len(lines) + 40
img = Image.new("RGB", (W, H), "white"); d = ImageDraw.Draw(img)
for i, l in enumerate(lines):
    d.text((20, 20 + i * lh), l, font=font, fill=(20, 20, 20))
img.save(png)
text = text.replace("```\n" + art + "\n```", f"![Figure 1. The deployed pilot.]({png})", 1)
open(dst, "w").write(text)
PY
cp -R media "$TMP/media"
# Word
pandoc "$TMP/doc.md" --from gfm --toc --toc-depth=2 --resource-path=".:$TMP" -o "$OUT/OpenHuman-on-OCI-architecture.docx"
python3 - "$OUT/OpenHuman-on-OCI-architecture.docx" <<'PY'
import sys
from docx import Document
from docx.shared import Pt, Inches
p = sys.argv[1]; doc = Document(p)
for s in doc.sections:
    s.left_margin = s.right_margin = Inches(0.8); s.top_margin = s.bottom_margin = Inches(0.9)
for name in ("Source Code", "Verbatim Char"):
    try:
        st = doc.styles[name]; st.font.size = Pt(7.5)
    except KeyError:
        pass
doc.save(p)
PY
# PDF
cat > "$TMP/head.tex" <<'TEX'
\usepackage{fvextra}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{commandchars=\\\{\},fontsize=\scriptsize,breaklines}
\fvset{fontsize=\scriptsize,breaklines}
\RecustomVerbatimEnvironment{verbatim}{Verbatim}{fontsize=\scriptsize,breaklines=true,breakanywhere=true}
\usepackage{etoolbox}
\AtBeginEnvironment{longtable}{\footnotesize}
TEX
pandoc "$TMP/doc.md" --from gfm --toc --toc-depth=2 --pdf-engine=xelatex \
  -V geometry:margin=0.8in -V mainfont="Helvetica Neue" -V monofont="Menlo" -V fontsize=10pt \
  -V colorlinks=true -V linkcolor=blue -V urlcolor=blue \
  -H "$TMP/head.tex" --resource-path=".:$TMP" -o "$OUT/OpenHuman-on-OCI-architecture.pdf"
rm -rf "$TMP"
ls -la "$OUT"
