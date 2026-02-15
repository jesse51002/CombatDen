package user

import "fmt"

// NotFoundError is returned when a user is not found.
type NotFoundError struct {
	UserID string
}

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("user not found: %s", e.UserID)
}

// DuplicateEmailError is returned when attempting to create a user with an existing email.
type DuplicateEmailError struct {
	Email string
}

func (e *DuplicateEmailError) Error() string {
	return fmt.Sprintf("user with email already exists: %s", e.Email)
}
