.PHONY: help run build test lint fmt clean sqlc install-tools check

# Default target
help:
	@echo "Available commands:"
	@echo "  make run           - Run the application"
	@echo "  make build         - Build the application"
	@echo "  make test          - Run tests"
	@echo "  make test-coverage - Run tests with coverage"
	@echo "  make check         - Format, lint, and clean (pre-commit)"
	@echo "  make lint          - Run linters"
	@echo "  make fmt           - Format code"
	@echo "  make sqlc          - Generate sqlc code"
	@echo "  make clean         - Clean build artifacts"
	@echo "  make install-tools - Install development tools"

# Run the application
run: sqlc
	@echo "Starting application..."
	@lsof -ti:8090 | xargs kill -9 2>/dev/null || true
	go run cmd/api/main.go

# Build the application
build: sqlc
	@echo "Building application..."
	go build -o bin/api cmd/api/main.go

# Run tests
test:
	@echo "Running tests..."
	go test -v -race ./...

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	go test -v -race -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

# Code quality check - format, lint, and clean
check: fmt lint clean
	@echo "✓ Code quality check complete!"

# Run linters
lint:
	go vet ./...

# Format code
fmt:
	@echo "Formatting code..."
	gofmt -w .
	goimports -w .
	go mod tidy

# Generate sqlc code
sqlc:
	@echo "Generating sqlc code..."
	sqlc generate

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -rf bin/
	rm -f coverage.out coverage.html
	go clean

# Install development tools
install-tools:
	@echo "Installing development tools..."
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install golang.org/x/tools/cmd/goimports@latest
	go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
	@echo "Tools installed successfully!"

supabase-start:
	npx supabase start
	npx supabase migration up

migration: supabase-start
	npx supabase db diff -f $(name)
	npx supabase migration up

make supabase-push:
	npx supabase db push
