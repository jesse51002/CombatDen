// Package config provides application configuration loaded from environment variables.
package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Environment represents the application environment.
type Environment string

const (
	EnvDev  Environment = "DEV"
	EnvQA   Environment = "QA"
	EnvProd Environment = "PROD"
)

// String returns the string representation of the environment.
func (e Environment) String() string {
	return string(e)
}

// IsValid checks if the environment value is valid.
func (e Environment) IsValid() bool {
	switch e {
	case EnvDev, EnvProd, EnvQA:
		return true
	default:
		return false
	}
}

// Config holds all application configuration.
type Config struct {
	// Server configuration
	ServerPort string
	ServerHost string
	Env        Environment

	// Supabase configuration
	SupabaseURL        string
	SupabaseAnonKey    string
	SupabaseServiceKey string

	// Database configuration
	DatabaseURL string
	Database    DatabaseConfig
}

// DatabaseConfig holds database connection pool configuration.
type DatabaseConfig struct {
	MaxConns          int32         // Maximum number of connections in the pool
	MinConns          int32         // Minimum number of connections in the pool
	MaxConnLifetime   time.Duration // Maximum lifetime of a connection
	MaxConnIdleTime   time.Duration // Maximum idle time before connection is closed
	HealthCheckPeriod time.Duration // Health check interval
}

// Load reads configuration from environment variables.
// It loads .env.dev for local development (when ENV is not set),
// or .env for other environments (when ENV is set).
func Load() (*Config, error) {
	// Check if ENV variable is set
	env := os.Getenv("ENV")

	// If ENV is not set, use .env.dev for local development
	// If ENV is set (DEV, QA, PROD, etc.), use .env or system env vars
	if env == "" {
		// Load .env.dev for local development
		if err := godotenv.Load(".env.dev"); err != nil {
			return nil, fmt.Errorf("failed to load .env.dev: %w", err)
		}
	} else {
		// ENV is set, try to load .env (ignore error if not present)
		_ = godotenv.Load()
	}

	config := &Config{
		ServerPort: getEnv("SERVER_PORT", "8080"),
		ServerHost: getEnv("SERVER_HOST", "0.0.0.0"),
		Env:        parseEnvironment(getEnv("ENV", string(EnvDev))),

		SupabaseURL:        getEnv("SUPABASE_URL", ""),
		SupabaseAnonKey:    getEnv("SUPABASE_ANON_KEY", ""),
		SupabaseServiceKey: getEnv("SUPABASE_SERVICE_KEY", ""),

		DatabaseURL: getEnv("DATABASE_URL", ""),
		Database: DatabaseConfig{
			MaxConns:          25,
			MinConns:          5,
			MaxConnLifetime:   1 * time.Hour,
			MaxConnIdleTime:   30 * time.Minute,
			HealthCheckPeriod: 1 * time.Minute,
		},
	}

	// Validate required configuration
	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("invalid configuration: %w", err)
	}

	return config, nil
}

// Validate checks that all required configuration values are set.
func (c *Config) Validate() error {
	if !c.Env.IsValid() {
		return fmt.Errorf("invalid ENV value: %s (must be one of: DEV, PROD, STAGING, TEST)", c.Env)
	}
	if c.SupabaseURL == "" {
		return fmt.Errorf("SUPABASE_URL is required")
	}
	if c.SupabaseAnonKey == "" {
		return fmt.Errorf("SUPABASE_ANON_KEY is required")
	}
	if c.DatabaseURL == "" {
		return fmt.Errorf("DATABASE_URL is required")
	}

	return nil
}

// parseEnvironment parses the environment string into an Environment type.
// It supports case-insensitive matching and common variations.
func parseEnvironment(env string) Environment {
	env = strings.ToUpper(strings.TrimSpace(env))

	switch env {
	case "DEV":
		return EnvDev
	case "QA":
		return EnvQA
	case "PROD":
		return EnvProd
	default:
		return EnvDev // Default to development
	}
}

// IsDevelopment returns true if the application is running in development mode.
func (c *Config) IsDev() bool {
	return c.Env == EnvDev
}

// IsProduction returns true if the application is running in production mode.
func (c *Config) IsProd() bool {
	return c.Env == EnvProd
}

// IsQA returns true if the application is running in QA mode.
func (c *Config) IsQA() bool {
	return c.Env == EnvQA
}

// getEnv retrieves an environment variable or returns a default value.
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
