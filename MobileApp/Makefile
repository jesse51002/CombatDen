.PHONY: help run run-ios run-release analyze format test clean get reset devices doctor

help:
	@echo "MobileApp — visual prototype Flutter app"
	@echo ""
	@echo "Targets:"
	@echo "  make run          Run on Android (default)"
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

run-phone:
	flutter run -d 52121FDAS0018S

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
