#!/usr/bin/env bash
# Stitch title + terminal demo + browser screenshot card + outro into the final cut.
# Inputs are produced by: python (cards, see docs), `vhs media/demo.tape` (demo.mp4).
set -euo pipefail
cd "$(dirname "$0")"
for f in title.mp4 demo.mp4 browser-card.mp4 outro.mp4; do [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }; done
# trim the terminal capture to what the demo actually took (+ typing and a tail), using the
# elapsed seconds the demo wrote; fall back to the full capture.
LEAD="${DEMO_LEAD_TRIM:-3}"   # seconds of typing/blank at the start to drop
# Trim only on a fresh capture (DEMO_TRIM=1): the committed demo.mp4 is already trimmed.
if [ "${DEMO_TRIM:-0}" = "1" ] && [ -f .demo-elapsed ]; then
  DUR=$(( $(cat .demo-elapsed) + 14 ))
  ffmpeg -y -loglevel error -ss "$LEAD" -i demo.mp4 -t "$DUR" -c:v libx264 -preset veryfast -crf 20 -an _demo-trim.mp4 && mv _demo-trim.mp4 demo.mp4
fi
# normalise every segment to the same size/fps/pixel format before concat
for f in title demo browser-card outro; do
  ffmpeg -y -loglevel error -i "$f.mp4" -vf "scale=1600:1000:force_original_aspect_ratio=decrease,pad=1600:1000:(ow-iw)/2:(oh-ih)/2:color=0x1e1e2e,fps=30,format=yuv420p" -an -c:v libx264 -preset veryfast -crf 20 "_$f.mp4"
done
printf "file '_title.mp4'\nfile '_demo.mp4'\nfile '_browser-card.mp4'\nfile '_outro.mp4'\n" > _list.txt
ffmpeg -y -loglevel error -f concat -safe 0 -i _list.txt -c copy openhuman-oci-showcase.mp4
rm -f _title.mp4 _demo.mp4 _browser-card.mp4 _outro.mp4 _list.txt
ffprobe -v error -show_entries format=duration:stream=width,height -of default=nw=1 openhuman-oci-showcase.mp4
ls -la openhuman-oci-showcase.mp4 | awk '{print $5" bytes"}'
