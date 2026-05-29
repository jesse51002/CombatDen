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

/// Dedicated read-only client for the public VideoService. Unauthenticated.
/// Fetches the approved feed for a **gym** ([gymId]); the server paginates and
/// groups it server-side.
class VideoApiClient {
  VideoApiClient({
    required this.baseUrl,
    required this.gymId,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // Generous: a cold call hydrates the whole feed server-side (the
        // one-shot preview groups every genre), so give it room to finish
        // instead of failing the screen.
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  final String baseUrl;

  /// The gym whose approved feed to fetch.
  final String gymId;

  late final Dio _dio;

  // Videos per genre in the one-shot home preview.
  static const int _kPreviewPerTag = 10;
  // Page size for a single genre's full "view all" list.
  static const int _kTagLimit = 100;

  /// `GET /gyms/{gymId}/videos/preview` — the home feed in ONE request: each
  /// genre is sampled individually (top [_kPreviewPerTag]) server-side, so no
  /// genre is starved by pagination. Flattened to a list; the selectors
  /// re-group it into per-tag carousels.
  Future<List<Video>> fetchPreview() async {
    try {
      final response = await _dio.get<dynamic>(
        '/gyms/$gymId/videos/preview',
        queryParameters: {'per_tag': _kPreviewPerTag},
      );
      final data = response.data;
      if (data is Map && data['sections'] is List) {
        return [
          for (final section in (data['sections'] as List).whereType<Map>())
            if (section['videos'] is List)
              for (final v in (section['videos'] as List).whereType<Map>())
                Video.fromJson(Map<String, dynamic>.from(v)),
        ];
      }
      throw const VideoFetchException(
        'Feed preview response was not a JSON object with a sections array',
      );
    } on DioException catch (e) {
      throw VideoFetchException('Feed preview fetch failed: ${e.message}');
    }
  }

  /// `GET /gyms/{gymId}/videos?video_type=…` — every video for one genre, for a
  /// carousel's "view all" screen (its own request so it isn't capped to the
  /// home preview's per-genre sample).
  Future<List<Video>> fetchTag(String tag) async {
    try {
      final response = await _dio.get<dynamic>(
        '/gyms/$gymId/videos',
        queryParameters: {'video_type': tag, 'limit': _kTagLimit},
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
