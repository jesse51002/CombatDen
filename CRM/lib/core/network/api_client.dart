import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:crm/core/config/environment.dart';
import 'package:crm/core/config/supabase_config.dart';
import 'package:crm/core/constants/env_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:dio/dio.dart';

/// A binary download from [ApiClient.getBytes]: the raw response [bytes] and
/// the server-provided download [filename] parsed from `Content-Disposition`
/// (null when the header is absent — the caller supplies a fallback name).
typedef BytesResponse = ({Uint8List bytes, String? filename});

/// Authenticated HTTP client for backend API calls.
///
/// Automatically attaches the Supabase JWT token
/// as a Bearer token on every request.
class ApiClient {
  late final Dio _dio;

  /// Called when a 401 cannot be recovered by
  /// refreshing the Supabase session.
  static VoidCallback? onUnauthorized;

  /// Creates an [ApiClient] configured with the
  /// API base URL from environment variables.
  ApiClient() {
    final baseUrl = EnvironmentConfig.get(
      EnvConstants.apiBaseUrl,
    );
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.add(_AuthInterceptor());
  }

  /// Sends a GET request to [path].
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _handleRequest(
      () => _dio.get<T>(
        path,
        queryParameters: queryParameters,
      ),
    );
  }

  /// Sends a POST request to [path] with optional
  /// [data] body and/or [queryParameters].
  ///
  /// [receiveTimeout] overrides the shared 30s response wait for THIS request
  /// only — for an endpoint whose server-side work legitimately runs longer
  /// than the default (the kiosk signup's start call, which creates
  /// subscriptions and charges a card inside one request). It follows the
  /// [getBytes] precedent exactly: only the *receive* wait moves, never
  /// `connectTimeout` — a host that can't be reached should still fail fast,
  /// and stretching the connect wait would just hide an offline kiosk behind a
  /// long spinner. Omit it and nothing changes; the client default is
  /// untouched.
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
  }) async {
    return _handleRequest(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: receiveTimeout == null
            ? null
            : Options(receiveTimeout: receiveTimeout),
      ),
    );
  }

  /// Sends a PUT request to [path] with optional
  /// [data] body.
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
  }) async {
    return _handleRequest(
      () => _dio.put<T>(path, data: data),
    );
  }

  /// Sends a DELETE request to [path] with optional [data] body and/or
  /// [queryParameters].
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    return _handleRequest(
      () => _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
      ),
    );
  }

  /// Sends a multipart/form-data POST request to [path].
  ///
  /// Pass a pre-built [FormData] (e.g. from [FormData.fromMap]
  /// with [MultipartFile.fromBytes]).  The base JSON
  /// Content-Type is overridden per-request so the auth
  /// interceptor still attaches and refreshes the JWT normally.
  Future<Response<T>> postMultipart<T>(
    String path, {
    required FormData data,
  }) async {
    return _handleRequest(
      () => _dio.post<T>(
        path,
        data: data,
        options: Options(contentType: 'multipart/form-data'),
      ),
    );
  }

  /// Sends a GET request that downloads a **binary** body (a report / export
  /// zip) at [path], returning the raw [BytesResponse.bytes] plus the download
  /// [BytesResponse.filename] parsed from the `Content-Disposition` header
  /// (null when the header is absent — the caller supplies a fallback name).
  ///
  /// Unlike [get], this calls `_dio.get` directly with a per-request
  /// [Options]: `ResponseType.bytes` so the body isn't JSON-decoded, and a
  /// **2-minute** `receiveTimeout` because a full-history export can take far
  /// longer than the shared 30s default (which would false-fail it). It still
  /// runs through [_handleRequest], so the JWT attach + 401 refresh-and-retry
  /// and the typed error mapping are preserved unchanged.
  Future<BytesResponse> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _handleRequest(
      () => _dio.get<List<int>>(
        path,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 2),
        ),
      ),
    );
    final data = response.data ?? const <int>[];
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final filename = _filenameFromContentDisposition(
      response.headers.value('content-disposition'),
    );
    return (bytes: bytes, filename: filename);
  }

  /// Parses the download filename out of a `Content-Disposition` header value,
  /// preferring the RFC 5987 `filename*=UTF-8''<pct-encoded>` form over a plain
  /// `filename="..."`. Returns null when [header] is null or carries no
  /// filename (the backend exposes this header via CORS, but it may still be
  /// absent — the caller then falls back to a client-side name).
  String? _filenameFromContentDisposition(String? header) {
    if (header == null) return null;
    final extended = RegExp(
      "filename\\*=(?:UTF-8'')?([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (extended != null) {
      final raw = extended.group(1)!.trim();
      try {
        return Uri.decodeComponent(raw);
      } catch (_) {
        return raw.isEmpty ? null : raw;
      }
    }
    final quoted = RegExp(
      'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header);
    final name = quoted?.group(1)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<Response<T>> _handleRequest<T>(
    Future<Response<T>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      if (e.type ==
              DioExceptionType.connectionTimeout ||
          e.type ==
              DioExceptionType.receiveTimeout ||
          e.type ==
              DioExceptionType.sendTimeout ||
          e.type ==
              DioExceptionType.connectionError) {
        throw NetworkException(
          'Network error: ${e.message}',
        );
      }
      if (e.response != null) {
        final body = e.response?.data;
        final statusCode = e.response?.statusCode;
        final data =
            body is Map ? body.cast<String, dynamic>() : null;
        // A 403 is an authorization failure (role not allowed), NOT a session
        // expiry — the 401 refresh/retry path in [_AuthInterceptor] is
        // untouched. Surface it as a distinct, friendlier exception; never
        // sign the user out on it.
        if (statusCode == 403) {
          throw ForbiddenException(
            statusCode: statusCode,
            detail: _extractDetail(body),
            data: data,
          );
        }
        throw ServerException(
          'Server error '
          '$statusCode: '
          '${e.response?.statusMessage}',
          statusCode: statusCode,
          detail: _extractDetail(body),
          data: data,
        );
      }
      throw NetworkException(
        'Unexpected error: ${e.message}',
      );
    }
  }

  /// Extracts the `detail` string from a FastAPI-style
  /// error body (`{"detail": "..."}`). Returns null
  /// when the body is missing, non-JSON, or has no
  /// string `detail` field.
  String? _extractDetail(Object? data) {
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }
}

/// Interceptor that attaches the Supabase JWT token
/// to every outgoing request and retries on 401 after
/// refreshing the session.
class _AuthInterceptor extends Interceptor {
  /// Upper bound on the 401 session refresh. gotrue treats a
  /// network/host-unreachable refresh failure as *retryable* and
  /// keeps retrying with backoff without emitting any event, so an
  /// unbounded `refreshSession()` can hang the request forever (and
  /// with it any boot-time gym fetch — the auth gate then spins
  /// indefinitely instead of redirecting to login). Capping it turns
  /// a stalled refresh into a clean sign-out via [onUnauthorized].
  static const Duration _refreshTimeout = Duration(seconds: 10);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final session =
        SupabaseConfig.client.auth.currentSession;
    final String? token = session?.accessToken;
    if (token != null) {
      options.headers['Authorization'] =
          'Bearer $token';
    } else {
      log(
        'No auth token available for '
        '${options.method} ${options.path}',
      );
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    try {
      final response = await SupabaseConfig
          .client.auth
          .refreshSession()
          .timeout(_refreshTimeout);
      final newToken =
          response.session?.accessToken;

      if (newToken == null) {
        ApiClient.onUnauthorized?.call();
        return handler.next(err);
      }

      // Retry the original request with the
      // refreshed token.
      final options = err.requestOptions;
      options.headers['Authorization'] =
          'Bearer $newToken';

      final retryResponse = await Dio().fetch<dynamic>(
        options,
      );
      return handler.resolve(retryResponse);
    } catch (e) {
      log(
        'Session refresh failed',
        error: e,
      );
      ApiClient.onUnauthorized?.call();
      return handler.next(err);
    }
  }
}
