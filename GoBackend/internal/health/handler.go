package health

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// Handler handles health check requests.
type Handler struct {
	startTime time.Time
}

// NewHandler creates a new health check handler.
func NewHandler() *Handler {
	return &Handler{
		startTime: time.Now().UTC(),
	}
}

// HealthResponse represents the health check response.
type HealthResponse struct {
	Status  string    `json:"status"`
	Uptime  string    `json:"uptime"`
	Time    time.Time `json:"time"`
	Version string    `json:"version"`
}

// Check handles the health check endpoint.
// @Summary Health check
// @Description Returns the health status of the API
// @Tags health
// @Produce json
// @Success 200 {object} HealthResponse
// @Router /health [get]
func (h *Handler) Check(c *gin.Context) {
	uptime := time.Since(h.startTime)

	c.JSON(http.StatusOK, HealthResponse{
		Status:  "healthy",
		Uptime:  uptime.String(),
		Time:    time.Now().UTC(),
		Version: "1.0.0",
	})
}
