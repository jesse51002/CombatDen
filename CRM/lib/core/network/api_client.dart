import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:crm/core/config/environment.dart';
import 'package:crm/core/config/supabase_config.dart';
import 'package:crm/core/constants/env_constants.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:dio/dio.dart';

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
  /// [data] body.
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
  }) async {
    return _handleRequest(
      () => _dio.post<T>(path, data: data),
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
        throw ServerException(
          'Server error '
          '${e.response?.statusCode}: '
          '${e.response?.statusMessage}',
          statusCode: e.response?.statusCode,
          detail: _extractDetail(body),
          data: body is Map
              ? body.cast<String, dynamic>()
              : null,
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
