package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yourorg/combatden-api/internal/config"
	"github.com/yourorg/combatden-api/internal/database"
	"github.com/yourorg/combatden-api/internal/logger"
	"github.com/yourorg/combatden-api/internal/router"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize logger
	appLogger := logger.New()
	appLogger.Info("Starting CombatDen API",
		"environment", cfg.Env,
		"port", cfg.ServerPort,
		"database_url", cfg.DatabaseURL,
	)

	// Initialize database connection
	db, err := database.New(context.Background(), cfg.DatabaseURL, cfg.Database)
	if err != nil {
		appLogger.Error("Failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	appLogger.Info("Connected to database",
		"environment", cfg.Env,
		"is_local", cfg.IsDev(),
	)

	// Set up router with all routes
	r := router.Setup(appLogger, cfg.IsDev())

	// Configure HTTP server
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%s", cfg.ServerHost, cfg.ServerPort),
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in a goroutine
	go func() {
		appLogger.Info("Server listening", "address", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			appLogger.Error("Server failed to start", "error", err)
			os.Exit(1)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	appLogger.Info("Shutting down server...")

	// Graceful shutdown with 5 second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		appLogger.Error("Server forced to shutdown", "error", err)
		os.Exit(1)
	}

	// Close database connection
	db.Close()
	appLogger.Info("Database connection closed")

	appLogger.Info("Server stopped gracefully")
}
