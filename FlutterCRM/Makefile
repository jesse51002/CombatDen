.PHONY: run-dev

# Run Flutter web app in development mode with hot reload
run-dev:
	@lsof -ti:8080 | xargs kill -9 2>/dev/null || true
	flutter run -d web-server --web-port 8080
