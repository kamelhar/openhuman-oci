#!/usr/bin/env bash
# Render every media/diagrams/*.d2 to SVG (d2) and to a 2x PNG (headless Chrome).
# Usage: media/diagrams/render.sh [name ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
names=("$@"); [ ${#names[@]} -eq 0 ] && names=($(ls *.d2 | sed 's/\.d2$//'))
for n in "${names[@]}"; do
  d2 --pad 24 "$n.d2" "$n.svg" >/dev/null
  read -r w h < <(python3 - "$n.svg" <<'PY'
import re,sys
s=open(sys.argv[1]).read(2000)
m=re.search(r'viewBox="[-\d.]+ [-\d.]+ ([\d.]+) ([\d.]+)"',s)
w,h=float(m.group(1)),float(m.group(2))
print(int(w)+2,int(h)+2)
PY
)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size="$w,$h" --screenshot="$PWD/$n.png" "file://$PWD/$n.svg" >/dev/null 2>&1
  echo "$n: ${w}x${h} -> $n.svg $n.png"
done
