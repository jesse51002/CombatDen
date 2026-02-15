package user

import (
	"context"
)

// Service defines the interface for user business logic.
type Service interface {
	GetUser(ctx context.Context, id string) (*UserResponse, error)
	GetUserByEmail(ctx context.Context, email string) (*UserResponse, error)
	ListUsers(ctx context.Context, limit, offset int32) ([]*UserResponse, error)
	CreateUser(ctx context.Context, req *CreateUserRequest) (*UserResponse, error)
	UpdateUser(ctx context.Context, id string, req *UpdateUserRequest) (*UserResponse, error)
	DeleteUser(ctx context.Context, id string) error
}

// service implements the Service interface.
type service struct {
	repo Repository
}

// NewService creates a new user service.
func NewService(repo Repository) Service {
	return &service{repo: repo}
}

// GetUser retrieves a user by ID.
func (s *service) GetUser(ctx context.Context, id string) (*UserResponse, error) {
	return s.repo.Get(ctx, id)
}

// GetUserByEmail retrieves a user by email.
func (s *service) GetUserByEmail(ctx context.Context, email string) (*UserResponse, error) {
	return s.repo.GetByEmail(ctx, email)
}

// ListUsers retrieves a list of users with pagination.
func (s *service) ListUsers(ctx context.Context, limit, offset int32) ([]*UserResponse, error) {
	return s.repo.List(ctx, limit, offset)
}

// CreateUser creates a new user.
func (s *service) CreateUser(ctx context.Context, req *CreateUserRequest) (*UserResponse, error) {
	// Add business logic validation here if needed
	return s.repo.Create(ctx, req)
}

// UpdateUser updates an existing user.
func (s *service) UpdateUser(ctx context.Context, id string, req *UpdateUserRequest) (*UserResponse, error) {
	// Add business logic validation here if needed
	return s.repo.Update(ctx, id, req)
}

// DeleteUser deletes a user.
func (s *service) DeleteUser(ctx context.Context, id string) error {
	return s.repo.Delete(ctx, id)
}
