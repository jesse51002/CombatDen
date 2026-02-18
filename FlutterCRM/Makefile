.PHONY: run run-prod run-web-dev

# Run Flutter app in dev mode (uses local Supabase)
run: kill_old
	flutter run --dart-define=ENVIRONMENT=dev -d web-server --web-port 8080

# Run Flutter app in prod mode (uses cloud Supabase)
run-prod: kill_old
	flutter run --dart-define=ENVIRONMENT=prod --release -d web-server --web-port 8080

# Run Flutter web app in development mode with hot reload
kill_old:
	@lsof -ti:8080 | xargs kill -9 2>/dev/null || true
