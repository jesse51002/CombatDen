import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/members/data/gym_detail.dart';
import 'package:crm/features/members/data/video_feed.dart';

/// Repository for reading real-gym content via the authed FastApiBackend.
///
/// Used in the admin preview path (when [selectedGym.gymId] is non-null) to
/// fetch the gym's showcase data (classes + rewards; the video spec is
/// cross-fetched from the videos domain) and video feed from UUID-keyed
/// endpoints that require a valid Supabase session.
///
/// Contrast with [VideoApiClient] / [GymApiClient] (public, package:http),
/// which serve the slug-keyed template catalog used by the public theme browser.
///
/// Layered per CRM convention:
///   Widget → GymContentRepository → ApiClient → backend.
class GymContentRepository {
  final ApiClient _apiClient;

  GymContentRepository(ApiClient apiClient) : _apiClient = apiClient;

  /// `GET /api/v1/gyms/{gymId}/showcase` — the real gym's showcase content
  /// (classes + rewards). Returns a [GymDetail] whose [GymDetail.gymId] is the
  /// real UUID.
  ///
  /// The showcase lives in the theme domain and no longer carries the video
  /// spec, so the spec is cross-fetched from the videos domain
  /// (`GET .../videos/spec`) and merged under the `spec` key — keeping the
  /// Content focus cards populated. A missing spec (404) just leaves it empty.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<GymDetail> fetchShowcase(String gymId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/showcase',
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty showcase response');
      }
      final spec = await _fetchSpecOrNull(gymId);
      final merged = Map<String, dynamic>.from(data);
      if (spec != null) {
        merged['spec'] = spec;
      }
      return GymDetail.fromJson(merged);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('fetchShowcase failed', error: e, stackTrace: st);
      throw ServerException('Failed to load gym showcase: $e');
    }
  }

  /// The gym's live video spec (`GET .../videos/spec`), or null when there is
  /// none (404) or the read fails — best-effort context for the showcase.
  Future<Map<String, dynamic>?> _fetchSpecOrNull(String gymId) async {
    try {
      final resp = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/videos/spec',
      );
      return resp.data;
    } catch (e, st) {
      // Log so transient 5xx/network failures aren't completely invisible;
      // return null so the showcase still renders without a spec.
      log('_fetchSpecOrNull failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// `GET /api/v1/gyms/{gymId}/videos/preview?per_tag=` — one [FeedSection]
  /// per tag, each capped to [perTag] videos. Identical JSON shape to the
  /// template preview endpoint; [FeedSection.fromJson] parses it unchanged.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<List<FeedSection>> fetchVideoPreview(
    String gymId, {
    int perTag = 10,
    bool rejected = false,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/videos/preview',
        queryParameters: {'per_tag': perTag, if (rejected) 'rejected': true},
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty preview response');
      }
      final raw = data['sections'];
      if (raw is! List) {
        throw const ServerException(
          'Missing sections array in preview response',
        );
      }
      return raw
          .whereType<Map>()
          .map((e) => FeedSection.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('fetchVideoPreview failed', error: e, stackTrace: st);
      throw ServerException('Failed to load video preview: $e');
    }
  }

  /// `GET /api/v1/gyms/{gymId}/videos?video_type=&limit=&offset=` — one page
  /// of the real gym's video feed. Identical JSON shape to the template feed
  /// endpoint; [Video.fromJson] parses it unchanged.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<VideoPage> fetchVideos(
    String gymId, {
    String? videoType,
    bool owner = false,
    bool rejected = false,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/videos',
        queryParameters: {
          'limit': limit,
          'offset': offset,
          if (videoType != null && videoType.isNotEmpty)
            'video_type': videoType,
          if (owner) 'owner': true,
          if (rejected) 'rejected': true,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty videos response');
      }
      final raw = data['videos'];
      if (raw is! List) {
        throw const ServerException('Missing videos array in response');
      }
      final videos = raw
          .whereType<Map>()
          .map((e) => Video.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      final total = (data['total'] as int?) ?? videos.length;
      return VideoPage(videos: videos, total: total);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('fetchVideos failed', error: e, stackTrace: st);
      throw ServerException('Failed to load gym videos: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/videos/lookup` — fetch a YouTube link's real
  /// metadata (title / channel / thumbnail / views / duration) WITHOUT adding
  /// it. Powers the "confirm these details before adding" preview. Returns the
  /// looked-up [Video].
  ///
  /// Throws [ServerException] / [NetworkException] on failure (e.g. a 400 when
  /// the URL isn't a YouTube link or the video doesn't exist).
  Future<Video> lookupVideo(String gymId, String url) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/videos/lookup',
        data: {'url': url},
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty lookup response');
      }
      return Video.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('lookupVideo failed', error: e, stackTrace: st);
      throw ServerException('Failed to look up video: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/videos` — add one owner-provided YouTube link
  /// to the gym's served feed. The backend extracts the id and fetches the
  /// video's real metadata from the YouTube Data API. Returns the resulting
  /// [Video].
  ///
  /// Throws [ServerException] / [NetworkException] on failure (e.g. a 400 when
  /// the URL isn't a recognisable YouTube link).
  Future<Video> addVideo(String gymId, String url) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/gyms/$gymId/videos',
        data: {'url': url},
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty add-video response');
      }
      return Video.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('addVideo failed', error: e, stackTrace: st);
      throw ServerException('Failed to add video: $e');
    }
  }

  /// `DELETE /api/v1/gyms/{gymId}/videos/{videoId}` — remove one video from the
  /// gym's served feed and log the removal (with the optional [reason]) to
  /// `gym_video_feed_removal`. The shared pool row is left untouched.
  /// Idempotent.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<void> removeVideo(
    String gymId,
    String videoId, {
    bool owner = false,
    String? reason,
  }) async {
    try {
      await _apiClient.delete<void>(
        '/api/v1/gyms/$gymId/videos/$videoId${owner ? '?owner=true' : ''}',
        data: (reason != null && reason.isNotEmpty) ? {'reason': reason} : null,
      );
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('removeVideo failed', error: e, stackTrace: st);
      throw ServerException('Failed to remove video: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/videos/{videoId}/keep` — un-reject a video
  /// (flip it back to the served feed; the reject audit is kept). The optional
  /// [reason] is stored as `accept_reason` and fed to the feed-learning refiner.
  /// Idempotent.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<void> keepVideo(
    String gymId,
    String videoId, {
    String? reason,
  }) async {
    try {
      await _apiClient.post<void>(
        '/api/v1/gyms/$gymId/videos/$videoId/keep',
        data: (reason != null && reason.isNotEmpty)
            ? {'accept_reason': reason}
            : null,
      );
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('keepVideo failed', error: e, stackTrace: st);
      throw ServerException('Failed to keep video: $e');
    }
  }
}
