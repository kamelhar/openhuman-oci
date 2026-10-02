#!/usr/bin/env bash
# Export docs/OPENHUMAN-ON-OCI.md to Word and PDF with the figures sized for the
# page; code blocks and margins are tightened.
# Usage: media/export-doc.sh [out-dir]   (default: ~/Documents/openhuman-oci)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Documents/openhuman-oci}"; mkdir -p "$OUT"
SRC=docs/OPENHUMAN-ON-OCI.md
TMP="$(mktemp -d)"
# Copy the source next to a media/ mirror so ../media/... resolves, and give every
# figure an explicit print width (Word does not auto-fit large bitmaps).
mkdir -p "$TMP/docs"; cp -R media "$TMP/media"
python3 - "$SRC" "$TMP/docs/doc.md" <<'PY'
import re, sys
src, dst = sys.argv[1:3]
text = open(src).read()
# "![alt](path)\n\n*Figure N. caption*" -> one pandoc figure whose caption is the italic text
text = re.sub(r"^!\[[^\]]*\]\(([^)]+)\)[ \t]*\n\n\*(Figure[^*]+)\*[ \t]*$", r"![\2](\1){width=6.5in}", text, flags=re.M)
text = re.sub(r"^(!\[[^\]]*\]\([^)]+\))\s*$", r"\1{width=6.5in}", text, flags=re.M)
open(dst, "w").write(text)
PY
# Word
pandoc "$TMP/docs/doc.md" --from markdown-raw_html-smart --toc --toc-depth=2 --resource-path="$TMP/docs" -o "$OUT/OpenHuman-on-OCI-architecture.docx"
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
\usepackage{caption}
\captionsetup{labelformat=empty,font=small,labelfont=bf}
\AtBeginEnvironment{longtable}{\footnotesize}
TEX
pandoc "$TMP/docs/doc.md" --from markdown-raw_html-smart --toc --toc-depth=2 --pdf-engine=xelatex \
  -V geometry:margin=0.8in -V mainfont="Helvetica Neue" -V monofont="Menlo" -V fontsize=10pt \
  -V colorlinks=true -V linkcolor=blue -V urlcolor=blue \
  -H "$TMP/head.tex" --resource-path="$TMP/docs" -o "$OUT/OpenHuman-on-OCI-architecture.pdf"
rm -rf "$TMP"
ls -la "$OUT"
