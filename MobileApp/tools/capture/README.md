# Capture harness — landing-page clips

Dev-only captures that render the real app screens to frame-exact webm
(1080×1920 for the reel, 1080×2340 for the booking + app-screen clips) for the
landing page:
- **Theme reel** (`make capture`) — the video feed (`VideosScreen`) scrolling to
  the bottom, once per theme, locked-camera synced.
- **"Perfectly timed content"** (`make capture-booking`) — the class-booking
  moment (class detail → ~1s loading dots → "Video Before Class"), once per
  discipline, branded to that discipline.
- **App-screen clips** (`make capture-app`) — **Home** (static), **Booking**
  (the "you're in" booked confirm), **Points**, and **Streak**, each branded to
  barre / muaythai / reformer.

Not part of the shipping app. The shipping-code touches are all opt-in and inert
in normal use: `captureController` on `VideosScreen`; `classData` on
`ClassScreen`; `captureContentOnly` on `ClassBookedScreen`; and the global
`captureRevealClock` (`lib/shared/widgets/animation/capture_reveal_clock.dart`),
read by `ScaleReveal`, `StaggeredReveal`, `CountUpText`, `LoadingDots`, the
points/streak intro controllers (`_PointSphere`/`_StreakOrbit`), and the streak
badge pulse — so the post-class celebration animations render frame-exact at any
clock value. All captures share `capture_frame.dart` (the fixed-size
`RepaintBoundary`), the uninstall-first 1× install, the per-clip pull+cleanup,
and `stitch.sh`.

## How it works

- **Deterministic offline capture.** A second Flutter entrypoint
  (`capture_main.dart`) mounts `VideosScreen` inside a fixed-size
  `RepaintBoundary` (`capture_stage.dart`: 360×640 logical at pixelRatio 3 →
  exactly **1080×1920**, device-independent). It drives the scroll frame-by-frame
  and writes one PNG per frame via `RepaintBoundary.toImage`. `stitch.sh` encodes
  the PNGs to webm on the host with system `ffmpeg`.
- **Bounded device storage.** A full reel is ~1MB/frame, which overflows a small
  emulator partition. So `capture.sh` orchestrates it: a **measure-only** run
  learns the shared locked-camera distance (no frames), then it captures **one
  theme per app run**, pulling that theme's frames to the host and deleting them
  from the device before the next. Peak device usage = one theme.
- **Locked camera.** Every theme scrolls the **same** pixel distance
  `D = min(maxScrollExtent across the batch)` over the same eased curve and frame
  count, so the scroll offset at frame `i` is byte-identical across themes — the
  clips can be crossfaded without the scroll jumping. (Themes change the font, so
  text line-heights drift a few px between themes; the *camera* stays exact.)
- **Theme → gym.** The feed is keyed by `selectedGym.gymId`, not the theme. The
  harness resolves each design id to its gym via `GymsPager` (the VideoService
  `GET /gyms` browser), exactly like the in-app style picker, then calls
  `selectedGym.select(...)`.

## Prerequisites

- A running **Android emulator** (default serial `emulator-5554`).
  > Linux desktop would be cleaner (host filesystem, no `adb`), but this box
  > (atomic Fedora / Bluefin) lacks the desktop toolchain (`clang`/`ninja`/
  > `cmake`/`gtk+-3.0`). If you set that up, `flutter run -d linux -t
  > tools/capture/capture_main.dart` works and writes straight to the host —
  > skip `adb pull` in `stitch.sh`.
- **Backends up:** `make api` in `../ThemeService` (:8000) and `../VideoService`
  (:8002). `make capture` opens the `adb reverse` tunnels for both.
- `ffmpeg` on the host PATH.

## Run

```bash
make capture                       # the theme reel, 9s @ 24fps
make capture THEMES=VinyasaFlow    # one theme
make capture SECONDS=6             # shorter clip = faster scroll (same distance)
make stitch                        # pull frames + encode -> LandingPage/assets/landing/
```

Tunables (via `make capture VAR=...`): `THEMES`, `SECONDS` (9), `FPS` (24).
A longer clip scrolls slower because the scroll distance is fixed. If you
override `FPS`, pass the same `FPS` to `make stitch`. Output:
`LandingPage/assets/landing/video-feed-scroll-<theme>.webm`.

## "Perfectly timed content" booking clips

```bash
make capture-booking            # the curated 12 disciplines
make capture-booking CLIPS=0    # just clip index 0 (muay_thai); CLIPS=0,2,7 for a subset
```

Each clip is a 3-phase timeline (`capture_booking_main.dart` + `booking_stage.dart`):
class detail (the discipline's real first class + photo, ~1.2s) → `LoadingDots`
(~1s) → the live "Video Before Class" screen (~2s) — the real flow's checkmark /
"Class Booked" / Continue steps are **skipped**. The curated list (one
representative gym per discipline family, all themes built) is baked into
`capture_booking_main.dart`; `CAPTURE_CLIP_INDEX` selects one. Gym+theme switch at
runtime via `selectedGym.select`, and the gym's classes come from
`GymRepository.detail()` (`GET /gyms/{id}`). Output:
`LandingPage/assets/landing/perfectly-timed-<discipline>.webm`. Tunables (dart-
defines): `CAPTURE_IMAGE_HOLD_MS` (600), `CAPTURE_SCROLL_MS` (3000),
`CAPTURE_DOTS_MS` (1000), `CAPTURE_VIDEO_MS` (4000), `CAPTURE_FPS` (24).

The same entrypoint also drives the **"you're in" confirm** variant via
`CAPTURE_BOOKING_END=confirm`: class detail → quick scroll → reserve tap → the
booked image + caption pop-in (the dots + video are skipped). The discipline can
be passed directly with `CAPTURE_GYM_ID` / `CAPTURE_THEME` / `CAPTURE_SLUG`
(overriding the curated list, so reformer works), which is how `capture-app`
invokes it. The booked-content reveal is driven by `captureRevealClock` (the
`ClassBookedScreen(captureContentOnly: true)` path).

## App-screen clips

```bash
make capture-app                          # 4 screens × 3 disciplines (12 clips)
make capture-app SCREENS=points           # just points × 3
make capture-app SCREENS=home,streak CLIPS=0   # a subset
```

`capture_app.sh` loops `(screen, discipline)` — one app run each, uninstall-first,
pull+wipe — then encodes everything with `stitch.sh PREFIX=""`. Screens:
- **home** — the real `HomeScreen` (its PageView opens on the not-booked
  class-schedule page), held static ~2s. `capture_app_main.dart` pre-warms the
  gym detail + class photos so the schedule isn't blank.
- **points** / **streak** — the post-class celebration bodies inside the real
  `PostClassScaffold` (framed faithfully, but the Continue CTA + close X are
  suppressed). The harness walks `captureRevealClock` 0→window (Points ~3.5s,
  Streak ~5.4s), driving the sphere/orbit intro, the count-up odometer, and the
  staggered reveals at true speed, then holds the settled frame ~2s.
- **booking** — routed to `capture_booking_main.dart` in confirm mode (above).

Each `(screen, discipline)` writes `capture/<screen>-<discipline>/`, encoded to
`LandingPage/assets/landing/<screen>-<discipline>.webm` (e.g. `points-barre.webm`,
`booking-muaythai.webm`). Disciplines: `barre` (classic_barre/ClassicBarre),
`muaythai` (muay_thai/KillerMuayThai), `reformer`
(reformer_contemporary/ReformerContemporary). The app-screen + confirm clips
render on the realistic-phone canvas (`kPhone*` in `capture_frame.dart`: 415
logical wide @ pixelRatio 2.6 → 1080×2340) so the 7-badge streak strip fits — it
overflows at the reel's 360. Tunables (dart-defines): `CAPTURE_HOLD_MS` (2000),
`CAPTURE_POINTS_MS` (3500), `CAPTURE_STREAK_MS` (5400), `CAPTURE_FPS` (24); env
(booking quick scroll): `SCROLL_MS` (1200), `IMAGE_HOLD_MS` (400).

## Static screenshots

```bash
make capture-shots                                       # default screens × 6 disciplines
make capture-shots SCREENS=videos                        # one screen × 6
make capture-shots SCREENS=home DISCS=bjj,boxing         # a subset
make capture-shots SCREENS=wins,booked DISCS=nogi        # stats-final + booking-completed
make capture-shots SCREENS=prevideo DISCS=nogi           # the "Video Before Class" still
```

`capture_app_main.dart` in `CAPTURE_SHOT` mode grabs a single static frame of one
screen:

- **home**, **rewards** (`PointsStoreScreen`), **videos** (`VideosScreen`) — a
  plain settled frame (no animation/intro/hold).
- **wins** — the "Today's wins" stats-final recap (`WinsBody`), **booked** — the
  "Class Booked" confirmation (`ClassBookedScreen(captureContentOnly: true)`),
  **prevideo** — the "Video Before Class" screen (`VideoReccScreen`). These pin the
  global capture clock past every reveal and grab a settled final frame (so the
  clock-aware reveals render fully revealed and the Wins sparkle burst settles).
  wins/booked are clean (no CTA/X), matching the points/streak clips.

The discipline is passed directly via `CAPTURE_GYM_ID/THEME/SLUG` (so any gym
works, not just the clip three); the gym is selected in `initState` so the
**content** (classes/rewards/feed, all keyed by `selectedGym.gymId`) matches the
theme. A cold theme can exceed `selectDesign`'s 5s fetch timeout, so the harness
retries the theme load before capturing. `capture_shots.sh` loops
`(screen, discipline)` — disciplines `bjj` (bjj_gi/ZenBJJ), `muaythai`, `boxing`
(boxing/SweetScienceBoxing), `barre`, `yoga` (vinyasa/VinyasaFlow), `crossfit`
(crossfit/CrossFitBox), `nogi` (no_gi_grappling/FrictionGrappling), `matpilates`
(mat_pilates/MatPilates), `flowbarre` (flow_barre/Barre3Flow) — and writes
`LandingPage/media-src/screenshots/<screen>-<discipline>.png`.

## Notes

- Frames are written to the app's external files dir on the device
  (`/sdcard/Android/data/com.combatden.mobile_app/files/capture/<theme>/`);
  `capture.sh` pulls each theme to `tools/capture/frames/` (gitignored) and wipes
  the device dir before the next theme. `stitch.sh` only encodes the local frames.
- The app `exit(0)`s when each run finishes, so `flutter run` returns on its own;
  `capture.sh` relaunches it per theme.
- Wiring the landing page to actually cycle/crossfade multiple theme clips is a
  separate follow-up; `feed.jsx` currently plays one webm.
