.PHONY: help run run-phone run-ios run-release tunnel tunnel-phone analyze format test clean get reset devices doctor capture capture-booking capture-app capture-shots stitch

# Physical device serial (from `adb devices` / `flutter devices`).
DEVICE := 52121FDAS0018S
# Emulator serial (from `adb devices`).
EMULATOR := emulator-5554

help:
	@echo "MobileApp — visual prototype Flutter app"
	@echo ""
	@echo "Targets:"
	@echo "  make run          Run on emulator (auto adb-reverse :8000/:8002 to backend)"
	@echo "  make run-phone    Run on physical device (USB adb-reverse tunnel to backend)"
	@echo "  make run-ios      Run on iOS simulator"
	@echo "  make run-release  Run on emulator in release mode (tunneled)"
	@echo "  make tunnel       (Re)open adb-reverse :8000/:8002 to the emulator"
	@echo "  make tunnel-phone (Re)open adb-reverse :8000/:8002 to the USB device"
	@echo "  make analyze      Static analysis (must be clean before committing)"
	@echo "  make format       Format every Dart file"
	@echo "  make test         Run all tests"
	@echo "  make get          flutter pub get"
	@echo "  make reset        Clean + get (full dependency rebuild)"
	@echo "  make clean        Clean build artifacts"
	@echo "  make devices      List connected devices / simulators"
	@echo "  make doctor       Flutter doctor"

# Tunnel the emulator's localhost:8000/8002 to the host so the app reaches the
# CustomizationService (:8000) and VideoService (:8002). adb reverse tunnels
# reset on an emulator/adb restart, so re-run before each session. Both
# services must be up: the FastApiBackend on :8000 (content -- gyms, classes,
# rewards, videos) and ThemeService on :8001 (customization).
run: tunnel
	flutter run -d $(EMULATOR)

# Same tunnels over USB to a physical device (Wi-Fi-independent — sidesteps
# router AP/client isolation), then run pointed at localhost. Re-run after
# unplugging/rebooting the device.
# No --dart-define here on purpose: the Dart defaults are already
# localhost:8001 for ThemeService and localhost:8000/api/v1 for the
# content API, and the tunnels below map exactly those two ports. Pinning
# them here a second time is how they went stale -- this target used to
# point CUST_BASE_URL at :8000 (the backend, which has no /apps route, so
# every theme fetch 404'd) and VIDEO_BASE_URL at :8002 (the standalone
# VideoService, whose HTTP API no longer exists). Override on the command
# line for a LAN IP instead of editing this.
run-phone: tunnel-phone
	flutter run -d $(DEVICE)

run-ios:
	flutter run -d ios

run-release: tunnel
	flutter run --release -d $(EMULATOR)

# Reverse-tunnel both backend ports. `tunnel` targets the emulator, `tunnel-phone`
# the USB device. Run standalone if the app is already running and only lost
# its tunnels (then hot-restart with R).
tunnel:
	adb -s $(EMULATOR) reverse tcp:8000 tcp:8000
	adb -s $(EMULATOR) reverse tcp:8001 tcp:8001

tunnel-phone:
	adb -s $(DEVICE) reverse tcp:8000 tcp:8000
	adb -s $(DEVICE) reverse tcp:8001 tcp:8001

# Landing-page theme reel: render the video feed scrolling, once per theme, as
# frame-exact 1080x1920 clips (tools/capture/). To keep device storage bounded,
# capture.sh measures all extents once, then captures one theme per app run,
# pulling+deleting each before the next. Backends must be up (`make api` in
# ../ThemeService and ../VideoService). Override THEMES=A,B / SECONDS / FPS.
#   make capture                       # the theme reel, 9s @ 24fps
#   make capture THEMES=VinyasaFlow SECONDS=6
# NOTE: if you override FPS, pass the same FPS to `make stitch` too.
capture:
	EMULATOR=$(EMULATOR) \
		$(if $(THEMES),THEMES=$(THEMES),) \
		$(if $(SECONDS),SECS=$(SECONDS),) \
		$(if $(FPS),FPS=$(FPS),) \
		bash tools/capture/capture.sh

# "Perfectly timed content": one class-booking clip per discipline (class detail
# -> ~1s loading dots -> "Video Before Class"), branded to each discipline.
# Curated 12 by default; CLIPS=0 (or 0,2,7) renders a subset by index. Outputs
# LandingPage/assets/landing/perfectly-timed-<slug>.webm.
#   make capture-booking
#   make capture-booking CLIPS=0
capture-booking:
	EMULATOR=$(EMULATOR) \
		$(if $(CLIPS),CLIPS=$(CLIPS),) \
		$(if $(FPS),FPS=$(FPS),) \
		bash tools/capture/capture_booking.sh

# Landing-page app-screen clips: home / booking / points / streak, each branded
# to barre / muaythai / reformer (12 total). home is held static ~2s; points and
# streak play the full post-class celebration (driven by the capture clock) then
# hold; booking is the "you're in" confirm clip (quick scroll -> reserve tap ->
# booked image+caption). SCREENS=/CLIPS= render a subset. Outputs
# LandingPage/assets/landing/<screen>-<discipline>.webm.
#   make capture-app
#   make capture-app SCREENS=points CLIPS=0
capture-app:
	EMULATOR=$(EMULATOR) \
		$(if $(SCREENS),SCREENS=$(SCREENS),) \
		$(if $(CLIPS),CLIPS=$(CLIPS),) \
		$(if $(FPS),FPS=$(FPS),) \
		bash tools/capture/capture_app.sh

# Static screenshots: one PNG each of the home / rewards / videos screens, per
# discipline (bjj/muaythai/boxing/barre/yoga/crossfit). SCREENS=/DISCS= subset.
# Outputs LandingPage/media-src/screenshots/<screen>-<discipline>.png.
#   make capture-shots
#   make capture-shots SCREENS=videos DISCS=bjj,boxing
capture-shots:
	EMULATOR=$(EMULATOR) \
		$(if $(SCREENS),SCREENS=$(SCREENS),) \
		$(if $(DISCS),DISCS=$(DISCS),) \
		$(if $(FPS),FPS=$(FPS),) \
		bash tools/capture/capture_shots.sh

# Encode the frames a capture run pulled into one webm per dir in
# LandingPage/assets/landing/. PREFIX sets the filename prefix.
stitch:
	$(if $(FPS),FPS=$(FPS),) $(if $(PREFIX),PREFIX=$(PREFIX),) bash tools/capture/stitch.sh

analyze:
	flutter analyze

format:
	dart format lib test

test:
	flutter test

get:
	flutter pub get

reset: clean get

clean:
	flutter clean

devices:
	flutter devices

doctor:
	flutter doctor
