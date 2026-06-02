#!/usr/bin/env bash
# Encode the captured PNG frames (pulled by capture.sh into tools/capture/frames/)
# into one webm per theme in LandingPage/media-src/ (the raw-source media area;
# the landing build pulls from there into assets/). Run AFTER `make capture`.
#
#   make stitch            # 24fps
#   FPS=24 make stitch
# If you captured with a non-default FPS, pass the same FPS here.
set -uo pipefail

FPS="${FPS:-24}"
# `-` (not `:-`): an explicitly-empty PREFIX="" stays empty (the app-screen
# clips bake the screen into the slug, e.g. points-barre), while an unset PREFIX
# still defaults. Output is <PREFIX><slug>.webm.
PREFIX="${PREFIX-video-feed-scroll-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # MobileApp/tools/capture
WORK="${WORK:-$HERE/frames}"
LANDING="$(cd "$HERE/../../../LandingPage/media-src" && pwd)"

command -v ffmpeg >/dev/null || { echo "ffmpeg not found on PATH"; exit 1; }
[ -d "$WORK" ] || { echo "No frames at $WORK — run 'make capture' first"; exit 1; }

shopt -s nullglob
encoded=0
for d in "$WORK"/*/; do
  theme="$(basename "$d")"
  n=$(ls "$d"frame_*.png 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then echo "skip $theme (no frames)"; continue; fi
  slug="$(echo "$theme" | tr '[:upper:]' '[:lower:]')"
  out="$LANDING/${PREFIX}${slug}.webm"
  echo "Encoding $theme ($n frames @ ${FPS}fps) -> $out"
  ffmpeg -y -framerate "$FPS" -start_number 0 -i "${d}frame_%04d.png" \
    -c:v libvpx-vp9 -pix_fmt yuv420p -b:v 0 -crf 32 "$out" \
    </dev/null >/dev/null 2>&1
  echo "  done: $(du -h "$out" | cut -f1)"
  encoded=$((encoded + 1))
done

echo "Encoded $encoded clip(s) to $LANDING"
