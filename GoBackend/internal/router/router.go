package router

import (
	"github.com/gin-gonic/gin"
	"github.com/yourorg/combatden-api/internal/health"
	"github.com/yourorg/combatden-api/internal/logger"
	"github.com/yourorg/combatden-api/internal/middleware"
)

// Setup configures and returns the main router with all routes registered.
func Setup(log logger.Logger, isDevelopment bool) *gin.Engine {
	// Set Gin mode
	if !isDevelopment {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()

	// Apply middleware in correct order
	r.Use(middleware.Recovery(log))     // 1. Panic recovery
	r.Use(middleware.CORS())            // 2. CORS
	r.Use(middleware.Logging(log))      // 3. Request logging
	r.Use(middleware.SecurityHeaders()) // 4. Security headers

	// Health check endpoint (no auth required)
	healthHandler := health.NewHandler()
	r.GET("/health", healthHandler.Check)

	// API v1 routes
	v1 := r.Group("/api/v1")
	{
		// Placeholder route - remove when adding actual routes
		v1.GET("/ping", func(c *gin.Context) {
			c.JSON(200, gin.H{"message": "pong"})
		})

		// Add authenticated routes here
		// Example:
		// v1.Use(middleware.Auth(supabaseClient))
		// users := v1.Group("/users")
		// {
		//     users.GET("", userHandler.List)
		//     users.GET("/:id", userHandler.Get)
		// }
	}

	return r
}
