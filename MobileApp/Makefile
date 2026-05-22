.PHONY: help run run-phone run-ios run-release tunnel tunnel-phone analyze format test clean get reset devices doctor

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
# services must be up (`make api` in ../CustomizationService and ../VideoService).
run: tunnel
	flutter run -d $(EMULATOR)

# Same tunnels over USB to a physical device (Wi-Fi-independent — sidesteps
# router AP/client isolation), then run pointed at localhost. Re-run after
# unplugging/rebooting the device.
run-phone: tunnel-phone
	flutter run -d $(DEVICE) --dart-define=CUST_BASE_URL=http://localhost:8000 --dart-define=VIDEO_BASE_URL=http://localhost:8002

run-ios:
	flutter run -d ios

run-release: tunnel
	flutter run --release -d $(EMULATOR)

# Reverse-tunnel both backend ports. `tunnel` targets the emulator, `tunnel-phone`
# the USB device. Run standalone if the app is already running and only lost
# its tunnels (then hot-restart with R).
tunnel:
	adb -s $(EMULATOR) reverse tcp:8000 tcp:8000
	adb -s $(EMULATOR) reverse tcp:8002 tcp:8002

tunnel-phone:
	adb -s $(DEVICE) reverse tcp:8000 tcp:8000
	adb -s $(DEVICE) reverse tcp:8002 tcp:8002

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
