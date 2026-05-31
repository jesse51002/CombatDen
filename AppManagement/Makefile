.PHONY: help run run-themes analyze format test get clean reset doctor \
	kill_old kill_old_themes \
	build-web deploy-install deploy-provision deploy-finalize deploy-upload deploy \
	build-themes deploy-themes-install deploy-themes-provision \
	deploy-themes-finalize deploy-themes-upload deploy-themes

help:
	@echo "AppManagement — gym admin web prototype"
	@echo ""
	@echo "  make run         Run admin web app on http://localhost:8081"
	@echo "  make run-themes  Run standalone theme browser on http://localhost:8082"
	@echo "  make analyze     Static analysis"
	@echo "  make format      Format every Dart file"
	@echo "  make test        Run all tests"
	@echo "  make get         flutter pub get"
	@echo "  make clean       Clean build artifacts"
	@echo "  make reset       clean + get"
	@echo "  make doctor      flutter doctor"

run: kill_old
	flutter run -d web-server --web-port 8081

# Standalone theme-browser target: same project, different entry point. Port
# 8082 so it can run alongside the admin app on 8081.
run-themes: kill_old_themes
	flutter run -d web-server --web-port 8082 --target lib/main_theme_browser.dart

kill_old:
	@lsof -ti:8081 | xargs kill -9 2>/dev/null || true

kill_old_themes:
	@lsof -ti:8082 | xargs kill -9 2>/dev/null || true

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

# --- Production deploy (S3 + CloudFront at app.combatden.net) ---------------
# Build the web bundle pointed at the production API subdomains. The two
# dart-defines override the localhost defaults in the VideoService/ThemeService
# carve-outs (see CLAUDE.md). Output: build/web.
build-web:
	flutter build web --release --base-href=/ --dart-define=CUST_BASE_URL=https://theme.combatden.net --dart-define=VIDEO_BASE_URL=https://video.combatden.net

# One-time AWS infra (mirrors LandingPage/deploy): bucket + ACM cert, then the
# CloudFront distribution. Each prints a Squarespace DNS record to add by hand.
deploy-install:
	cd deploy && poetry install

deploy-provision:
	cd deploy && poetry run python provision.py

deploy-finalize:
	cd deploy && poetry run python finalize.py

deploy-upload:
	cd deploy && poetry run python upload.py

# Build fresh + push to S3 + invalidate CloudFront. Run after provision/finalize
# and the DNS records are in place.
deploy: build-web deploy-upload

# --- Standalone theme browser deploy (S3 + CloudFront at themes.combatden.net) -
# Same project, the theme-browser entry point. Same two API dart-defines as the
# admin build (the carve-out backends are shared). Output: build/web — so admin
# and themes deploys are sequential, never simultaneous. Infra mirrors deploy/
# but targets its own bucket/domain (see deploy-themes/config.py).
build-themes:
	flutter build web --release --base-href=/ --target lib/main_theme_browser.dart --dart-define=CUST_BASE_URL=https://theme.combatden.net --dart-define=VIDEO_BASE_URL=https://video.combatden.net

deploy-themes-install:
	cd deploy-themes && poetry install

deploy-themes-provision:
	cd deploy-themes && poetry run python provision.py

deploy-themes-finalize:
	cd deploy-themes && poetry run python finalize.py

deploy-themes-upload:
	cd deploy-themes && poetry run python upload.py

deploy-themes: build-themes deploy-themes-upload
