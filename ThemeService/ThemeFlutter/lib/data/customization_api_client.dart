import 'package:dio/dio.dart';

import 'package:theme_flutter/data/models/customization_styles_page.dart';

/// Thrown on any customization fetch failure; the service
/// catches it and degrades to disk/defaults.
class ThemeFetchException implements Exception {
  final String message;
  const ThemeFetchException(this.message);

  @override
  String toString() => message;
}

/// Dedicated read-only client for the public
/// ThemeService. App-agnostic, unauthenticated, short
/// timeouts so app startup never hangs on it.
///
/// The service URL and request path are package-internal — the
/// app only supplies which app/design to load. (A URL-validation
/// API key will be added here later; not needed yet.)
class ThemeApiClient {
  /// Base URL of the ThemeService. Package-internal
  /// infrastructure — change here for a different deployment.
  /// Override at launch with `--dart-define=CUST_BASE_URL=<url>`.
  ///
  /// Default is `localhost`, used together with an adb reverse tunnel
  /// (`adb reverse tcp:8001 tcp:8001`) so the device reaches the host's
  /// server over the USB cable — Wi‑Fi-independent (no LAN IP, no AP
  /// isolation). The tunnel must be re-set after unplugging/reboot.
  /// Without adb reverse, pass `--dart-define=CUST_BASE_URL=http://<host-LAN-IP>:8001`.
  static const String _baseUrl = String.fromEnvironment(
    'CUST_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );

  ThemeApiClient({
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

  /// The request path for a given design (defaults to the one this
  /// client was built with). [design] lets the live style switch
  /// fetch a different preset without rebuilding the client.
  String _outputPath([String? design]) => '/apps/$appId/${design ?? designId}';

  /// `GET /apps/{appId}/{designId}` — the resolved customization.
  /// Pass [designId] to fetch a different preset than the default.
  Future<Map<String, dynamic>> fetchOutput({String? designId}) async {
    try {
      final response = await _dio.get<dynamic>(_outputPath(designId));
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw const ThemeFetchException(
        'ThemeConfig response was not a JSON object',
      );
    } on DioException catch (e) {
      throw ThemeFetchException(
        'ThemeConfig fetch failed: ${e.message}',
      );
    }
  }

  /// `GET /apps/{appId}/styles` — one page of the app's selectable
  /// styles (design name + celebration image), with the post-filter
  /// total so callers can detect end-of-list. [query] is a substring
  /// match on id or display name; `null` / empty returns every style.
  /// Same degrade-on-failure contract as [fetchOutput].
  Future<ThemeStylesPage> fetchStylesPage({
    int offset = 0,
    int limit = 20,
    String? query,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '/apps/$appId/styles',
        queryParameters: {
          'offset': offset,
          'limit': limit,
          if (query != null && query.isNotEmpty) 'q': query,
        },
      );
      final data = response.data;
      if (data is Map) {
        return ThemeStylesPage.fromJson(
          Map<String, dynamic>.from(data),
          resolveImageUrl,
        );
      }
      throw const ThemeFetchException(
        'Styles response was not a JSON object',
      );
    } on DioException catch (e) {
      throw ThemeFetchException(
        'Styles fetch failed: ${e.message}',
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
