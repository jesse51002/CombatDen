import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:app_management/features/members/data/video_feed.dart';

/// Read-only client for the public VideoService. This is the one piece of
/// the prototype that talks to a real backend: the member feed is pulled
/// live so the admin previews real thumbnails, not mock art.
///
/// Base URL defaults to localhost; override at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host>:8002`. The feed is fetched for a
/// **theme** ([designId]); the server resolves the theme to its gym and serves
/// that gym's approved feed, so the preview's videos change with the selected
/// theme.
class VideoApiClient {
  VideoApiClient({
    String? baseUrl,
    required this.designId,
  }) : baseUrl = baseUrl ?? _kDefaultBaseUrl;

  final String baseUrl;
  final String designId;

  static const String _kDefaultBaseUrl = String.fromEnvironment(
    'VIDEO_BASE_URL',
    defaultValue: 'http://localhost:8002',
  );

  /// `GET /themes/{designId}/videos` — the theme's gym feed (single-tenant).
  /// Returns an empty list on any failure so the UI can degrade quietly.
  Future<List<Video>> fetchFeed() async {
    final uri = Uri.parse('$baseUrl/themes/$designId/videos');
    final response = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('Video feed fetch failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['videos'] is List) {
      return (data['videos'] as List)
          .whereType<Map>()
          .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }
    throw Exception('Video feed response missing a videos array');
  }
}
