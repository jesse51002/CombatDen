import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/videos/data/models/gym_videos_feed.dart';
import 'package:mobile_app/features/videos/data/models/member_video_rec.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';

/// Repository for the member's video surface — the personalized gym feed, the
/// single rotating-category recommendation, and recording an open (click) of
/// either a recommendation or a video picked out of the feed.
///
/// Layered per convention: Bloc → MemberVideosRepository → ApiClient →
/// backend. Every route is scoped to the selected member; the bloc threads
/// `gymId` + `memberId` from the SelectedMember global.
class MemberVideosRepository {
  final ApiClient _apiClient;

  MemberVideosRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/videos` → one page of
  /// the gym's served feed, personalized to the member. [videoType] filters to
  /// a single genre (the category tabs); omitting it returns the whole feed
  /// ("All"). `big_group` is deliberately NOT sent — the tabs drive the feed by
  /// genre, and the two params are mutually exclusive server-side.
  Future<GymVideosFeed> fetchFeed({
    required String gymId,
    required String memberId,
    VideoGenre? videoType,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/videos',
        queryParameters: {
          if (videoType != null) 'video_type': videoType.name,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return GymVideosFeed.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('fetchFeed failed', error: e, stackTrace: st);
      throw ServerException('Failed to load videos: $e');
    }
  }

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/video-rec` → the
  /// member's next single rotating-category recommendation. A 404 (no category
  /// yields a video) surfaces as a [ServerException] with `statusCode == 404` —
  /// the bloc maps that to an empty state, not an error.
  Future<MemberVideoRec> fetchRec({
    required String gymId,
    required String memberId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/video-rec',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return MemberVideoRec.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('fetchRec failed', error: e, stackTrace: st);
      throw ServerException('Failed to load your recommendation: $e');
    }
  }

  /// `POST /api/v1/member/gyms/{gymId}/members/{memberId}/video-rec/{recId}/click`
  /// — record the member opening a recommendation (idempotent; logs a
  /// `video_clicked` activity server-side). Best-effort: the caller
  /// fire-and-forgets so a failure never blocks navigation.
  Future<void> recordRecClick({
    required String gymId,
    required String memberId,
    required String recId,
  }) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/video-rec/$recId/click',
      );
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('recordRecClick failed', error: e, stackTrace: st);
      throw ServerException('Failed to record the click: $e');
    }
  }

  /// `POST /api/v1/member/gyms/{gymId}/members/{memberId}/videos/{videoId}/click`
  /// — record the member opening a video they picked out of the FEED (the
  /// hero, a carousel, a genre list, the profile's level-up carousel). Logs a
  /// `video_clicked` activity server-side, which is what the taste profile
  /// learns from; without it personalization would only ever see the videos
  /// the system itself recommended.
  ///
  /// **Append-only, never deduped** — two opens of the same video log two
  /// rows, because a re-watch is real signal. That is deliberately the
  /// opposite of [recordRecClick], which is idempotent per served rec, so a
  /// rec open must post THAT route and not this one.
  ///
  /// Best-effort: the caller fire-and-forgets so a failure never blocks the
  /// YouTube launch.
  Future<void> recordVideoClick({
    required String gymId,
    required String memberId,
    required String videoId,
  }) async {
    try {
      await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/videos/$videoId/click',
      );
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('recordVideoClick failed', error: e, stackTrace: st);
      throw ServerException('Failed to record the video click: $e');
    }
  }
}
