import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/video_config/data/models/video_config_models.dart';

/// Repository for the video-config agent domain.
///
/// All endpoints are gym-employee-gated; the [ApiClient] attaches the
/// Supabase JWT automatically. Base path:
/// `GET|PUT /api/v1/gyms/{gymId}/video-config`
/// `POST    /api/v1/gyms/{gymId}/video-config/agent`
/// `POST    /api/v1/gyms/{gymId}/video-config/generate-queries`
/// `POST    /api/v1/gyms/{gymId}/video-config/refine-from-feed`
///
/// Placed next to [GymContentRepository] per the CRM data-layer convention.
/// Layered per CRM convention:
///   Screen → Bloc → VideoConfigRepository → ApiClient → backend.
class VideoConfigRepository {
  final ApiClient _apiClient;

  VideoConfigRepository(ApiClient apiClient) : _apiClient = apiClient;

  static const String _base = '/api/v1/gyms';

  /// `GET /api/v1/gyms/{gymId}/video-config`
  ///
  /// Returns null on 404 (no config has been authored yet).
  /// Throws [ServerException] / [NetworkException] on other failures.
  Future<VideoConfigView?> getConfig(String gymId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '$_base/$gymId/video-config',
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty video-config response');
      }
      return VideoConfigView.fromJson(data);
    } on ServerException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('VideoConfigRepository.getConfig failed', error: e, stackTrace: st);
      throw ServerException('Failed to load video config: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/video-config/agent`
  ///
  /// Sends [message] and the full [history] from the previous turn (null on
  /// the first turn). Returns the agent's reply, an optional draft, and the
  /// updated history to pass back on the next turn.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<AgentTurnResult> agentTurn(
    String gymId,
    String message, {
    List<dynamic>? history,
  }) async {
    try {
      // The backend explicitly accepts `history: null` on the first turn.
      final response = await _apiClient.post<Map<String, dynamic>>(
        '$_base/$gymId/video-config/agent',
        data: <String, dynamic>{
          'message': message,
          'history': history,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty agent response');
      }
      return AgentTurnResult.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('VideoConfigRepository.agentTurn failed', error: e, stackTrace: st);
      throw ServerException('Agent turn failed: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/video-config/generate-queries`
  ///
  /// Generates a list of YouTube search queries from the given criteria.
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<List<String>> generateQueries(
    String gymId, {
    List<String>? disciplines,
    String? videosDesc,
    String? avoidDesc,
    int? count,
  }) async {
    try {
      // Build the body imperatively — all fields are optional and the backend
      // rejects keys with null values for non-nullable typed fields.
      final body = <String, dynamic>{};
      if (disciplines != null) body['disciplines'] = disciplines;
      if (videosDesc != null) body['videos_desc'] = videosDesc;
      if (avoidDesc != null) body['avoid_desc'] = avoidDesc;
      if (count != null) body['count'] = count;
      final response = await _apiClient.post<Map<String, dynamic>>(
        '$_base/$gymId/video-config/generate-queries',
        data: body,
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty queries response');
      final raw = data['queries'];
      if (raw is! List) {
        throw const ServerException('Missing queries array in response');
      }
      return raw.whereType<String>().toList(growable: false);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log(
        'VideoConfigRepository.generateQueries failed',
        error: e,
        stackTrace: st,
      );
      throw ServerException('Failed to generate queries: $e');
    }
  }

  /// `PUT /api/v1/gyms/{gymId}/video-config`
  ///
  /// Saves a [VideoConfigDraft] and returns the committed [VideoConfigView].
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<VideoConfigView> saveConfig(
    String gymId,
    VideoConfigDraft draft,
  ) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '$_base/$gymId/video-config',
        data: draft.toJson(),
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty save response');
      return VideoConfigView.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('VideoConfigRepository.saveConfig failed', error: e, stackTrace: st);
      throw ServerException('Failed to save video config: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/video-config/refine-from-feed`
  ///
  /// Refines the config from recent feed interactions.
  /// Returns null on 404 (nothing new to learn — treat as a no-op).
  /// Throws [ServerException] / [NetworkException] on other failures.
  Future<VideoConfigView?> refineFromFeed(String gymId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '$_base/$gymId/video-config/refine-from-feed',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty refine response');
      return VideoConfigView.fromJson(data);
    } on ServerException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log(
        'VideoConfigRepository.refineFromFeed failed',
        error: e,
        stackTrace: st,
      );
      throw ServerException('Failed to refine from feed: $e');
    }
  }
}
