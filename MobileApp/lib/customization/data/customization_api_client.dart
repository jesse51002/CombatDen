import 'package:dio/dio.dart';

/// Thrown on any customization fetch failure; the service
/// catches it and degrades to disk/defaults.
class CustomizationFetchException implements Exception {
  final String message;
  const CustomizationFetchException(this.message);

  @override
  String toString() => message;
}

/// Dedicated read-only client for the public
/// CustomizationService. App-agnostic, unauthenticated, short
/// timeouts so app startup never hangs on it.
///
/// The service URL and request path are package-internal — the
/// app only supplies which app/design to load. (A URL-validation
/// API key will be added here later; not needed yet.)
class CustomizationApiClient {
  /// Base URL of the CustomizationService. Package-internal
  /// infrastructure — change here for a different deployment.
  /// `10.0.2.2` is the Android emulator's alias for the host's
  /// `localhost` (use the host LAN IP for a physical device).
  static const String _baseUrl = 'http://10.0.2.2:8000';

  CustomizationApiClient({
    required this.appId,
    required this.designId,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  final String appId;
  final String designId;

  late final Dio _dio;

  /// Resolved base URL (used to absolutise relative image URLs).
  String get baseUrl => _baseUrl;

  /// The request path for this app/design (the "sub url").
  String get _outputPath => '/apps/$appId/$designId';

  /// `GET /apps/{appId}/{designId}` — the resolved customization.
  Future<Map<String, dynamic>> fetchOutput() async {
    try {
      final response = await _dio.get<dynamic>(_outputPath);
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const CustomizationFetchException(
        'Customization response was not a JSON object',
      );
    } on DioException catch (e) {
      throw CustomizationFetchException(
        'Customization fetch failed: ${e.message}',
      );
    }
  }

  /// Absolutises a possibly-relative image slot URL.
  String resolveImageUrl(String raw) {
    if (raw.startsWith('http://') ||
        raw.startsWith('https://')) {
      return raw;
    }
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$base$path';
  }
}
