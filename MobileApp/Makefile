.PHONY: help run run-phone run-ios run-release analyze format test clean get reset devices doctor

# Physical device serial (from `adb devices` / `flutter devices`).
DEVICE := 52121FDAS0018S

help:
	@echo "MobileApp — visual prototype Flutter app"
	@echo ""
	@echo "Targets:"
	@echo "  make run          Run on Android (default)"
	@echo "  make run-phone    Run on physical device (USB adb-reverse tunnel to backend)"
	@echo "  make run-ios      Run on iOS simulator"
	@echo "  make run-release  Run on Android in release mode"
	@echo "  make analyze      Static analysis (must be clean before committing)"
	@echo "  make format       Format every Dart file"
	@echo "  make test         Run all tests"
	@echo "  make get          flutter pub get"
	@echo "  make reset        Clean + get (full dependency rebuild)"
	@echo "  make clean        Clean build artifacts"
	@echo "  make devices      List connected devices / simulators"
	@echo "  make doctor       Flutter doctor"

run:
	flutter run -d emulator-5554

# Tunnel the phone's localhost:8000 to the host's localhost:8000 over USB
# (Wi-Fi-independent — sidesteps router AP/client isolation), then run
# pointed at localhost. Re-run after unplugging/rebooting the device.
# The CustomizationService (`make api` in ../CustomizationService) must be up.
run-phone:
	adb -s $(DEVICE) reverse tcp:8000 tcp:8000
	flutter run -d $(DEVICE) --dart-define=CUST_BASE_URL=http://localhost:8000

run-ios:
	flutter run -d ios

run-release:
	flutter run --release -d emulator-5554

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
