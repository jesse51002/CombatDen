package middleware

import (
	"time"

	"github.com/gin-gonic/gin"
	"github.com/yourorg/combatden-api/internal/logger"
)

// Logging returns a middleware that logs HTTP requests.
func Logging(log logger.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		// Process request
		c.Next()

		// Log request details
		duration := time.Since(start)
		status := c.Writer.Status()

		log.Info("HTTP request",
			"method", method,
			"path", path,
			"status", status,
			"duration", duration.String(),
			"ip", c.ClientIP(),
		)
	}
}
