import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:crm/features/members/data/video_feed.dart';

/// Read-only client for the public VideoService. This is part of the
/// prototype's read-only VideoService carve-out: the member feed is pulled
/// live so the admin previews real thumbnails, not mock art.
///
/// Base URL defaults to localhost; override at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host>:8002`. The feed is fetched by
/// **gym** ([gymId]) — the selected gym — and paginated server-side, so the
/// preview's videos change with the selected gym.
class VideoApiClient {
  VideoApiClient({
    String? baseUrl,
    required this.gymId,
  }) : baseUrl = baseUrl ?? _kDefaultBaseUrl;

  final String baseUrl;
  final String gymId;

  static const String _kDefaultBaseUrl = String.fromEnvironment(
    'VIDEO_BASE_URL',
    defaultValue: 'http://localhost:8002',
  );

  // Generous so a cold call that hydrates a big feed (or the one-shot preview)
  // has room to finish instead of failing a row.
  static const Duration _kTimeout = Duration(seconds: 30);

  /// `GET /gyms/{gymId}/videos` — one page of the gym's feed.
  ///
  /// Each genre section fetches its own slice: pass [videoType] to filter to a
  /// single genre, [limit]/[offset] to page. Set [rejected] to pull the scan's
  /// rejected list instead of the approved feed (the rejected-videos section,
  /// where the admin can keep one back). Returns the page's videos plus the
  /// pre-pagination [VideoPage.total] for that filter (so a "View all"/"Load
  /// more" knows whether more remain). Throws on any failure so the UI can
  /// degrade.
  Future<VideoPage> fetchFeed({
    String? videoType,
    bool rejected = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/gyms/$gymId/videos').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (videoType != null && videoType.isNotEmpty) 'video_type': videoType,
        if (rejected) 'rejected': 'true',
      },
    );
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_kTimeout);
    if (response.statusCode != 200) {
      throw Exception('Video feed fetch failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['videos'] is List) {
      final videos = (data['videos'] as List)
          .whereType<Map>()
          .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      final total = (data['total'] as int?) ?? videos.length;
      return VideoPage(videos: videos, total: total);
    }
    throw Exception('Video feed response missing a videos array');
  }

  /// `GET /gyms/{gymId}/videos/preview` — the whole "All" view in ONE request:
  /// one [FeedSection] per genre in the feed, each capped to [perTag] videos,
  /// sampled server-side so no genre is starved. Replaces firing a request per
  /// genre row (which saturated the browser's connection limit and timed out).
  /// [rejected] previews the scan's rejected list. Throws so the UI can degrade.
  Future<List<FeedSection>> fetchPreview({
    bool rejected = false,
    int perTag = 10,
  }) async {
    final uri = Uri.parse('$baseUrl/gyms/$gymId/videos/preview').replace(
      queryParameters: {
        'per_tag': '$perTag',
        if (rejected) 'rejected': 'true',
      },
    );
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(_kTimeout);
    if (response.statusCode != 200) {
      throw Exception('Feed preview fetch failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['sections'] is List) {
      return (data['sections'] as List)
          .whereType<Map>()
          .map((e) => FeedSection.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }
    throw Exception('Feed preview response missing a sections array');
  }
}
