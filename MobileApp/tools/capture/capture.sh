#!/usr/bin/env bash
# Orchestrate the theme-reel capture so device storage stays bounded: measure all
# extents once (no frames), then capture ONE theme per app run, pulling its frames
# to the host and deleting them from the device before the next theme. Every clip
# shares the locked-camera distance learned in the measure pass.
#
# Driven by `make capture` (which maps SECONDS -> SECS to dodge bash's special
# $SECONDS). Frames land in tools/capture/frames/<theme>/; then run `make stitch`.
set -uo pipefail

APP_ID="com.combatden.mobile_app"
DEVICE_DIR="/sdcard/Android/data/${APP_ID}/files/capture"
EMULATOR="${EMULATOR:-emulator-5554}"
SECS="${SECS:-9}"
FPS="${FPS:-24}"
THEMES="${THEMES:-VinyasaFlow,KillerMuayThai,HyroxPrep,RunClub,ZenBJJ,ClassicBarre}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/frames"
ENTRY="tools/capture/capture_main.dart"   # relative to the MobileApp dir (CWD)

command -v adb >/dev/null     || { echo "adb not found on PATH"; exit 1; }
command -v flutter >/dev/null || { echo "flutter not found on PATH"; exit 1; }

# The emulator is space-tight. Reinstalling a freshly-built APK (each run has
# different --dart-defines) OVER the old one needs ~2x the APK size transiently
# and fails with "not enough space". Uninstalling first makes every install 1x.
uninstall_app() { adb -s "$EMULATOR" uninstall "$APP_ID" >/dev/null 2>&1 || true; }

# Backends reachable from the device.
adb -s "$EMULATOR" reverse tcp:8000 tcp:8000 >/dev/null
adb -s "$EMULATOR" reverse tcp:8002 tcp:8002 >/dev/null

# ── 1. Measure pass: learn the shared locked-camera distance (writes no frames).
# NB: redirect to a file, do NOT pipe `flutter run` (piping its stdout makes it
# bail right after dependency resolution in this non-interactive context).
echo "== measuring scroll extents for: $THEMES =="
MLOG="$(mktemp)"
uninstall_app
flutter run -d "$EMULATOR" -t "$ENTRY" \
  --dart-define=CAPTURE_THEMES="$THEMES" \
  --dart-define=CAPTURE_MEASURE_ONLY=true > "$MLOG" 2>&1
grep -E 'EXTENT |DISTANCE=' "$MLOG" || true
D="$(grep -oE 'DISTANCE=[0-9.]+' "$MLOG" | head -1 | cut -d= -f2)"
rm -f "$MLOG"
if [ -z "$D" ] || awk "BEGIN{exit !($D+0<=0)}"; then
  echo "ERROR: measure pass produced no usable distance (D='$D'). A feed likely"
  echo "       failed to load — re-run, or check the VideoService (:8002)."
  exit 1
fi
echo "== locked-camera distance D=$D px =="

# ── 2. Capture pass: one theme per run, pulled + cleaned before the next.
rm -rf "$WORK"; mkdir -p "$WORK"
IFS=',' read -ra THEME_ARR <<< "$THEMES"
for raw in "${THEME_ARR[@]}"; do
  t="$(echo "$raw" | xargs)"   # trim whitespace
  [ -n "$t" ] || continue
  echo "== capturing $t (${SECS}s @ ${FPS}fps, D=$D) =="
  adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
  uninstall_app
  flutter run -d "$EMULATOR" -t "$ENTRY" \
    --dart-define=CAPTURE_THEMES="$t" \
    --dart-define=CAPTURE_DISTANCE="$D" \
    --dart-define=CAPTURE_SECONDS="$SECS" \
    --dart-define=CAPTURE_FPS="$FPS"
  adb -s "$EMULATOR" pull "$DEVICE_DIR/$t" "$WORK/$t" >/dev/null
  adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
  n=$(ls "$WORK/$t"/frame_*.png 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then
    echo "ERROR: $t produced 0 frames (install or feed failed). Aborting."
    exit 1
  fi
  echo "   pulled $n frames -> $WORK/$t"
done

echo "== capture complete. Frames in $WORK. Run 'make stitch' to encode. =="
