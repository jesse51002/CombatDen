package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/yourorg/combatden-api/internal/logger"
)

// Recovery returns a middleware that recovers from panics and logs the error.
func Recovery(log logger.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if err := recover(); err != nil {
				log.Error("Panic recovered",
					"error", err,
					"path", c.Request.URL.Path,
					"method", c.Request.Method,
				)

				c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
					"error": "Internal server error",
				})
			}
		}()

		c.Next()
	}
}
