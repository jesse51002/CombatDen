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

  /// The error body's `detail` when it is a plain string
  /// (FastAPI's default `{"detail": "..."}` shape). Null when
  /// `detail` is structured (a map/list) — read [data] then.
  final String? detail;

  /// The raw decoded error response body (e.g.
  /// `{"detail": {...}}`). Carries the structured `detail` a
  /// FastAPI handler can return as an object — the caller reads
  /// `data['detail']` directly. Null when the body is missing or
  /// not a JSON map.
  final Map<String, dynamic>? data;

  const ServerException(
    this.message, {
    this.statusCode,
    this.detail,
    this.data,
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

/// Thrown when the standalone sign endpoint returns 409 because the gym
/// published a newer waiver version between the load and the sign.
/// The caller should ask the user to close and re-open the sign dialog so
/// they see and acknowledge the updated text.
class WaiverStaleVersionException implements Exception {
  const WaiverStaleVersionException();

  @override
  String toString() =>
      'This waiver was updated. Please close and re-open to sign the latest version.';
}

/// One (member, waiver) pair that is missing a signature,
/// returned in a [WaiverGateException].
class WaiverGateItem {
  final String memberId;
  final String waiverId;
  final String name;

  const WaiverGateItem({
    required this.memberId,
    required this.waiverId,
    required this.name,
  });

  factory WaiverGateItem.fromJson(Map<String, dynamic> json) {
    return WaiverGateItem(
      memberId: json['member_id'] as String,
      waiverId: json['waiver_id'] as String,
      name: json['name'] as String,
    );
  }
}

/// Thrown when the start-memberships POST (or its preview) returns 422
/// because one or more required waivers are unsigned.
///
/// The CRM wizard intercepts this to route to the sign-waivers step instead
/// of the results step.
class WaiverGateException implements Exception {
  final String message;
  final List<WaiverGateItem> unsigned;

  const WaiverGateException({
    required this.message,
    required this.unsigned,
  });

  @override
  String toString() => message;
}

/// Thrown when an approve/reject on a redemption returns HTTP 409,
/// meaning another staff member has already decided it.
class RedemptionAlreadyDecidedException implements Exception {
  const RedemptionAlreadyDecidedException();

  @override
  String toString() =>
      'This redemption has already been decided by another staff member.';
}
