#!/usr/bin/env bash
# Capture static screenshots (one PNG each) of the home / rewards / videos
# screens, branded to each discipline — via capture_app_main.dart in CAPTURE_SHOT
# mode. One app run per (screen, discipline), uninstall-first, pulling the single
# frame to LandingPage/media-src/screenshots/<screen>-<discipline>.png.
#
#   make capture-shots                                 # 3 screens × 6 disciplines
#   make capture-shots SCREENS=videos                  # one screen × 6
#   make capture-shots SCREENS=home DISCS=bjj,muaythai # a subset
set -uo pipefail

APP_ID="com.combatden.mobile_app"
DEVICE_DIR="/sdcard/Android/data/${APP_ID}/files/capture"
EMULATOR="${EMULATOR:-emulator-5554}"
FPS="${FPS:-24}"

SCREENS="${SCREENS:-home rewards videos}"
SCREENS="${SCREENS//,/ }"
DISCS="${DISCS:-bjj muaythai boxing barre yoga crossfit}"
DISCS="${DISCS//,/ }"

# discipline slug -> "gym_id theme"
gym_for() { case "$1" in
  bjj)      echo "bjj_gi ZenBJJ" ;;
  muaythai) echo "muay_thai KillerMuayThai" ;;
  boxing)   echo "boxing SweetScienceBoxing" ;;
  barre)    echo "classic_barre ClassicBarre" ;;
  yoga)     echo "vinyasa VinyasaFlow" ;;
  crossfit) echo "crossfit CrossFitBox" ;;
  *) echo "" ;;
esac; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/frames"
OUT="$(cd "$HERE/../../../LandingPage/media-src" && pwd)/screenshots"
ENTRY="tools/capture/capture_app_main.dart"
cd "$HERE/../.." || { echo "cannot cd to MobileApp root"; exit 1; }

command -v adb >/dev/null     || { echo "adb not found on PATH"; exit 1; }
command -v flutter >/dev/null || { echo "flutter not found on PATH"; exit 1; }

uninstall_app() { adb -s "$EMULATOR" uninstall "$APP_ID" >/dev/null 2>&1 || true; }

adb -s "$EMULATOR" reverse tcp:8000 tcp:8000 >/dev/null
adb -s "$EMULATOR" reverse tcp:8002 tcp:8002 >/dev/null

mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
for screen in $SCREENS; do
  for disc in $DISCS; do
    read -r gym theme <<<"$(gym_for "$disc")"
    if [ -z "$gym" ]; then echo "skip unknown discipline: $disc"; continue; fi
    slug="${screen}-${disc}"
    echo "== screenshot $slug ($gym / $theme) =="
    adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
    uninstall_app
    flutter run -d "$EMULATOR" -t "$ENTRY" \
      --dart-define=CAPTURE_SHOT=true \
      --dart-define=CAPTURE_SCREEN="$screen" \
      --dart-define=CAPTURE_GYM_ID="$gym" \
      --dart-define=CAPTURE_THEME="$theme" \
      --dart-define=CAPTURE_SLUG="$disc" \
      --dart-define=CAPTURE_FPS="$FPS"
    rm -rf "$WORK/_pull"; mkdir -p "$WORK/_pull"
    adb -s "$EMULATOR" pull "$DEVICE_DIR" "$WORK/_pull" >/dev/null 2>&1 || true
    fpng="$(find "$WORK/_pull" -type f -name 'frame_0000.png' 2>/dev/null | head -1)"
    if [ -n "$fpng" ]; then
      cp "$fpng" "$OUT/${slug}.png"
      echo "   -> $OUT/${slug}.png"
    else
      echo "   WARNING: no screenshot pulled for $slug"
    fi
    rm -rf "$WORK/_pull"
    adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
  done
done

echo "== done -> $OUT =="
