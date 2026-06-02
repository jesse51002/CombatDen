#!/usr/bin/env bash
# Orchestrate the landing-page app-screen clips: one app run per (screen,
# discipline), pulling each clip's frames to the host and deleting them from the
# device before the next. Device storage stays bounded; installs are 1x
# (uninstall-first), as in capture_booking.sh.
#
# Screens: home, booking, points, streak. Disciplines: barre, muaythai, reformer.
# home/points/streak run capture_app_main.dart; booking runs the existing
# capture_booking_main.dart in its "you're in" confirm mode (a quick scroll →
# reserve tap → booked image+caption). Every clip's frames land in
# tools/capture/frames/<screen>-<discipline>/, encoded to
# LandingPage/assets/landing/<screen>-<discipline>.webm (stitch PREFIX="").
#
#   make capture-app                          # all 4 screens × 3 disciplines (12)
#   make capture-app SCREENS=points           # just points × 3
#   make capture-app SCREENS=home,streak CLIPS=0   # a subset
set -uo pipefail

APP_ID="com.combatden.mobile_app"
DEVICE_DIR="/sdcard/Android/data/${APP_ID}/files/capture"
EMULATOR="${EMULATOR:-emulator-5554}"
FPS="${FPS:-24}"
# Booking "quick scroll" timings (ms) — faster than the perfectly-timed clip's 3s.
SCROLL_MS="${SCROLL_MS:-1200}"
IMAGE_HOLD_MS="${IMAGE_HOLD_MS:-400}"

SCREENS="${SCREENS:-home booking points streak}"
SCREENS="${SCREENS//,/ }"
INDICES="${CLIPS:-0 1 2}"
INDICES="${INDICES//,/ }"

# Discipline table, indexed by CLIPS value (0..2).
GYM_IDS=(classic_barre muay_thai reformer_contemporary)
THEMES=(ClassicBarre KillerMuayThai ReformerContemporary)
DISC_SLUGS=(barre muaythai reformer)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/frames"
APP_ENTRY="tools/capture/capture_app_main.dart"
BOOKING_ENTRY="tools/capture/capture_booking_main.dart"
# Run from the MobileApp root so the relative `flutter run -t tools/...` entries
# resolve no matter where this script was invoked from.
cd "$HERE/../.." || { echo "cannot cd to MobileApp root"; exit 1; }

command -v adb >/dev/null     || { echo "adb not found on PATH"; exit 1; }
command -v flutter >/dev/null || { echo "flutter not found on PATH"; exit 1; }

uninstall_app() { adb -s "$EMULATOR" uninstall "$APP_ID" >/dev/null 2>&1 || true; }

adb -s "$EMULATOR" reverse tcp:8000 tcp:8000 >/dev/null
adb -s "$EMULATOR" reverse tcp:8002 tcp:8002 >/dev/null

rm -rf "$WORK"; mkdir -p "$WORK"
for screen in $SCREENS; do
  for i in $INDICES; do
    gym="${GYM_IDS[$i]}"; theme="${THEMES[$i]}"; disc="${DISC_SLUGS[$i]}"
    slug="${screen}-${disc}"
    echo "== capturing $slug =="
    adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
    uninstall_app
    if [ "$screen" = "booking" ]; then
      flutter run -d "$EMULATOR" -t "$BOOKING_ENTRY" \
        --dart-define=CAPTURE_GYM_ID="$gym" \
        --dart-define=CAPTURE_THEME="$theme" \
        --dart-define=CAPTURE_SLUG="$slug" \
        --dart-define=CAPTURE_BOOKING_END=confirm \
        --dart-define=CAPTURE_SCROLL_MS="$SCROLL_MS" \
        --dart-define=CAPTURE_IMAGE_HOLD_MS="$IMAGE_HOLD_MS" \
        --dart-define=CAPTURE_FPS="$FPS"
    else
      flutter run -d "$EMULATOR" -t "$APP_ENTRY" \
        --dart-define=CAPTURE_SCREEN="$screen" \
        --dart-define=CAPTURE_CLIP_INDEX="$i" \
        --dart-define=CAPTURE_FPS="$FPS"
    fi
    # The harness writes capture/<slug>/; pull it, then lift the slug dir
    # (wherever adb nested it) into WORK by locating its frames.
    rm -rf "$WORK/_pull"; mkdir -p "$WORK/_pull"
    adb -s "$EMULATOR" pull "$DEVICE_DIR" "$WORK/_pull" >/dev/null 2>&1 || true
    fpng="$(find "$WORK/_pull" -type f -name 'frame_0000.png' 2>/dev/null | head -1)"
    if [ -n "$fpng" ]; then
      sdir="$(dirname "$fpng")"
      rm -rf "$WORK/$slug"; mv "$sdir" "$WORK/$slug"
      echo "   pulled $(ls "$WORK/$slug"/frame_*.png 2>/dev/null | wc -l) frames -> $WORK/$slug"
    else
      echo "   WARNING: no frames pulled for $slug"
    fi
    rm -rf "$WORK/_pull"
    adb -s "$EMULATOR" shell rm -rf "$DEVICE_DIR"
  done
done

echo "== encoding to <screen>-<discipline>.webm =="
FPS="$FPS" PREFIX="" bash "$HERE/stitch.sh"
