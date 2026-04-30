.PHONY: help run analyze format test get clean reset doctor kill_old

help:
	@echo "AppManagement — gym admin web prototype"
	@echo ""
	@echo "  make run        Run web app on http://localhost:8081"
	@echo "  make analyze    Static analysis"
	@echo "  make format     Format every Dart file"
	@echo "  make test       Run all tests"
	@echo "  make get        flutter pub get"
	@echo "  make clean      Clean build artifacts"
	@echo "  make reset      clean + get"
	@echo "  make doctor     flutter doctor"

run: kill_old
	flutter run -d web-server --web-port 8081

kill_old:
	@lsof -ti:8081 | xargs kill -9 2>/dev/null || true

analyze:
	flutter analyze

format:
	dart format lib test

test:
	flutter test

get:
	flutter pub get

clean:
	flutter clean

reset: clean get

doctor:
	flutter doctor
