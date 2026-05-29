import 'package:dio/dio.dart';

import 'package:mobile_app/features/videos/data/video.dart';

/// Thrown on any video-feed fetch failure; the repository catches it and
/// degrades to an empty feed.
class VideoFetchException implements Exception {
  final String message;
  const VideoFetchException(this.message);

  @override
  String toString() => message;
}

/// Dedicated read-only client for the public VideoService. Unauthenticated,
/// short timeouts so a screen never hangs on it. Mirrors
/// `ThemeApiClient`. Fetches the feed for a **theme** (design id);
/// the server resolves the theme to its gym and serves that gym's approved feed.
class VideoApiClient {
  VideoApiClient({
    required this.baseUrl,
    required this.designId,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  final String baseUrl;

  /// The active customization design id whose gym feed to fetch.
  final String designId;

  late final Dio _dio;

  /// `GET /themes/{designId}/videos` — the theme's gym feed (single-tenant).
  Future<List<Video>> fetchFeed() async {
    try {
      final response = await _dio.get<dynamic>(
        '/themes/$designId/videos',
      );
      final data = response.data;
      if (data is Map && data['videos'] is List) {
        return (data['videos'] as List)
            .whereType<Map>()
            .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      }
      throw const VideoFetchException(
        'Video feed response was not a JSON object with a videos array',
      );
    } on DioException catch (e) {
      throw VideoFetchException('Video feed fetch failed: ${e.message}');
    }
  }
}
