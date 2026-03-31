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
        sendTimeout: const Duration(seconds: 30),
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

  /// Sends a DELETE request to [path].
  Future<Response<T>> delete<T>(String path) async {
    return _handleRequest(
      () => _dio.delete<T>(path),
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
        throw ServerException(
          'Server error '
          '${e.response?.statusCode}: '
          '${e.response?.statusMessage}',
        );
      }
      throw NetworkException(
        'Unexpected error: ${e.message}',
      );
    }
  }
}

/// Interceptor that attaches the Supabase JWT token
/// to every outgoing request.
class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final String? token = SupabaseConfig
        .client.auth.currentSession?.accessToken;
    if (token != null) {
      options.headers['Authorization'] =
          'Bearer $token';
    }
    handler.next(options);
  }
}
