#!/usr/bin/env bash
# Stitch the research showcase: title-research + demo-research (trimmed) + outro-research.
set -euo pipefail
cd "$(dirname "$0")"
for f in title-research.mp4 demo-research.mp4 outro-research.mp4; do [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }; done
LEAD="${DEMO_LEAD_TRIM:-3}"
if [ -f .demo-research-elapsed ]; then
  DUR=$(( $(cat .demo-research-elapsed) + 14 ))
  ffmpeg -y -loglevel error -ss "$LEAD" -i demo-research.mp4 -t "$DUR" -c:v libx264 -preset veryfast -crf 20 -an _d.mp4 && mv _d.mp4 demo-research.mp4
fi
for f in title-research demo-research outro-research; do
  ffmpeg -y -loglevel error -i "$f.mp4" -vf "scale=1600:1000:force_original_aspect_ratio=decrease,pad=1600:1000:(ow-iw)/2:(oh-ih)/2:color=0x1e1e2e,fps=30,format=yuv420p" -an -c:v libx264 -preset veryfast -crf 20 "_$f.mp4"
done
printf "file '_title-research.mp4'\nfile '_demo-research.mp4'\nfile '_outro-research.mp4'\n" > _list.txt
ffmpeg -y -loglevel error -f concat -safe 0 -i _list.txt -c copy openhuman-oci-research-showcase.mp4
rm -f _title-research.mp4 _demo-research.mp4 _outro-research.mp4 _list.txt
ffprobe -v error -show_entries format=duration:stream=width,height -of default=nw=1 openhuman-oci-research-showcase.mp4
ls -la openhuman-oci-research-showcase.mp4 | awk '{print $5" bytes"}'
