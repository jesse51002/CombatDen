/// Thrown when the backend returns an error
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
  String toString() => detail != null ? '$message — $detail' : message;
}

/// Thrown when the backend returns `403 Forbidden` — the signed-in user's
/// role lacks permission for the action. Distinct from a `401` (an expired
/// session, recovered by the interceptor's refresh-and-retry): a 403 means
/// the user is authenticated but not allowed, so it never triggers a
/// sign-out. A subtype of [ServerException], so existing `on ServerException`
/// handlers still catch it; catch [ForbiddenException] first to show the
/// role-specific message.
class ForbiddenException extends ServerException {
  const ForbiddenException({
    int? statusCode = 403,
    String? detail,
    Map<String, dynamic>? data,
  }) : super(
          'You don\'t have permission to do that. Your role may have '
          'changed — sign out and back in if this persists.',
          statusCode: statusCode,
          detail: detail,
          data: data,
        );
}

/// Thrown when a network request fails
class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);

  @override
  String toString() => message;
}
