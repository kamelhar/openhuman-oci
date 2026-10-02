#!/usr/bin/env bash
# Build the Word edition of docs/OPENHUMAN-ON-OCI.md and the PDF rendered from it:
# cover, title page with document control, contents with page numbers, Oracle Sans
# styles, running header and page numbers, styled tables, page-width figures.
# Usage: media/export-doc.sh [out-dir]   (default: ~/Documents/openhuman-oci)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$HOME/Documents/openhuman-oci}"
python3 media/cover.py --out media >/dev/null
python3 media/build-word.py --out "$OUT"
ls -la "$OUT"
