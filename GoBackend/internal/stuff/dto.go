package user

import "time"

// CreateUserRequest represents the request to create a new user.
type CreateUserRequest struct {
	Email string `json:"email" binding:"required,email"`
	Name  string `json:"name" binding:"required,min=2,max=100"`
}

// UpdateUserRequest represents the request to update a user.
// All fields are optional (pointers).
type UpdateUserRequest struct {
	Name *string `json:"name,omitempty" binding:"omitempty,min=2,max=100"`
}

// UserResponse represents a user in API responses.
type UserResponse struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
