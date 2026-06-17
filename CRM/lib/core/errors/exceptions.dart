/// Custom exception types for authentication and data operations
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

/// Thrown when login credentials are invalid
class InvalidCredentialsException extends AuthException {
  const InvalidCredentialsException()
      : super('Invalid email or password. Please try again.');
}

/// Thrown when attempting to register with an existing email
class UserAlreadyExistsException extends AuthException {
  const UserAlreadyExistsException()
      : super('An account with this email already exists.');
}

/// Thrown when password doesn't meet requirements
class WeakPasswordException extends AuthException {
  const WeakPasswordException()
      : super('Password must be at least 8 characters with a letter and number.');
}

/// Thrown when email is not confirmed
class EmailNotConfirmedException extends AuthException {
  const EmailNotConfirmedException()
      : super('Please verify your email address before logging in.');
}

/// Thrown when backend returns an error
class ServerException implements Exception {
  final String message;
  final int? statusCode;
  final String? detail;
  const ServerException(
    this.message, {
    this.statusCode,
    this.detail,
  });

  @override
  String toString() =>
      detail != null ? '$message — $detail' : message;
}

/// Thrown by the gym repository when the backend
/// returns a `409 Conflict` on gym creation. The
/// `detail` string is part of the API contract and
/// must be switched on by the caller to decide UX.
class GymConflictException implements Exception {
  final String detail;
  const GymConflictException(this.detail);

  @override
  String toString() => 'GymConflictException: $detail';
}

/// Thrown when network request fails
class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);

  @override
  String toString() => message;
}

/// Thrown when database operation fails
class DatabaseException implements Exception {
  final String message;
  const DatabaseException(this.message);

  @override
  String toString() => message;
}

/// Thrown when a mutation is blocked because the target
/// membership is part of an in-progress background task.
/// Triggered by a 409 from the backend.
class MembershipInTaskException implements Exception {
  final String message;
  const MembershipInTaskException(this.message);

  @override
  String toString() => message;
}
