import 'package:dio/dio.dart';

import 'package:mobile_app/customization/data/models/customization_style.dart';

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
  /// Override at launch with `--dart-define=CUST_BASE_URL=<url>`.
  ///
  /// Default is `localhost`, used together with an adb reverse tunnel
  /// (`adb reverse tcp:8000 tcp:8000`) so the device reaches the host's
  /// server over the USB cable — Wi‑Fi-independent (no LAN IP, no AP
  /// isolation). The tunnel must be re-set after unplugging/reboot.
  /// Without adb reverse, pass `--dart-define=CUST_BASE_URL=http://<host-LAN-IP>:8000`.
  static const String _baseUrl = String.fromEnvironment(
    'CUST_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

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
      throw const CustomizationFetchException(
        'Customization response was not a JSON object',
      );
    } on DioException catch (e) {
      throw CustomizationFetchException(
        'Customization fetch failed: ${e.message}',
      );
    }
  }

  /// `GET /apps/{appId}/styles` — the app's selectable styles
  /// (design name + celebration image). Same degrade-on-failure
  /// contract as [fetchOutput].
  Future<List<CustomizationStyle>> fetchStyles() async {
    try {
      final response = await _dio.get<dynamic>('/apps/$appId/styles');
      final data = response.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (e) => CustomizationStyle.fromJson(
                Map<String, dynamic>.from(e),
                resolveImageUrl,
              ),
            )
            .where((s) => s.id.isNotEmpty)
            .toList(growable: false);
      }
      throw const CustomizationFetchException(
        'Styles response was not a JSON array',
      );
    } on DioException catch (e) {
      throw CustomizationFetchException(
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
