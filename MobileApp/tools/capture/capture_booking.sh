#!/usr/bin/env bash
# Orchestrate the "Perfectly timed content" booking clips: one app run per clip
# (selected by index into the curated list in capture_booking_main.dart),
# pulling each clip's frames to the host and deleting them from the device before
# the next. Device storage stays bounded; installs are 1x (uninstall-first).
#
# Driven by `make capture-booking`. Frames land in tools/capture/frames/<slug>/;
# this then encodes them to LandingPage/assets/landing/perfectly-timed-<slug>.webm.
#
#   make capture-booking                 # all 12 clips
#   make capture-booking CLIPS=0         # just clip index 0 (muay_thai)
#   make capture-booking CLIPS=0,2,7     # a subset
set -uo pipefail

APP_ID="com.combatden.mobile_app"
DEVICE_DIR="/sdcard/Android/data/${APP_ID}/files/capture"
EMULATOR="${EMULATOR:-emulator-5554}"
FPS="${FPS:-24}"
INDICES="${CLIPS:-0 1 2 3 4 5 6 7 8 9 10 11}"   # space- or comma-separated
INDICES="${INDICES//,/ }"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/frames"
ENTRY="tools/capture/capture_booking_main.dart"

command -v adb >/dev/null     || { echo "adb not found on PATH"; exit 1; }
command -v flutter >/dev/null || { echo "flutter not found on PATH"; exit 1; }

# 1x installs on the space-tight emulator (see capture.sh for the why).
uninstall_app() { adb -s "$EMULATOR" uninstall "$APP_ID" >/dev/null 2>&1 || true; }

adb -s "$EMULATOR" reverse tcp:8000 tcp:8000 >/dev/null
adb -s "$EMULATOR" reverse tcp:8002 tcp:8002 >/dev/null

rm -rf "$WORK"; mkdir -p "$WORK"
for i in $INDICES; do
  echo "== capturing booking clip index $i =="
  adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
  uninstall_app
  flutter run -d "$EMULATOR" -t "$ENTRY" \
    --dart-define=CAPTURE_CLIP_INDEX="$i" \
    --dart-define=CAPTURE_FPS="$FPS"
  # The harness writes capture/<slug>/; pull the whole capture dir, then lift the
  # slug dir (wherever adb nested it) up into WORK by locating its frames.
  rm -rf "$WORK/_pull"; mkdir -p "$WORK/_pull"
  adb -s "$EMULATOR" pull "$DEVICE_DIR" "$WORK/_pull" >/dev/null 2>&1 || true
  fpng="$(find "$WORK/_pull" -type f -name 'frame_0000.png' 2>/dev/null | head -1)"
  if [ -n "$fpng" ]; then
    sdir="$(dirname "$fpng")"; slug="$(basename "$sdir")"
    rm -rf "$WORK/$slug"; mv "$sdir" "$WORK/$slug"
    echo "   pulled $(ls "$WORK/$slug"/frame_*.png 2>/dev/null | wc -l) frames -> $WORK/$slug"
  else
    echo "   WARNING: no frames pulled for index $i"
  fi
  rm -rf "$WORK/_pull"
  adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
done

echo "== encoding to perfectly-timed-<slug>.webm =="
FPS="$FPS" PREFIX="perfectly-timed-" bash "$HERE/stitch.sh"
