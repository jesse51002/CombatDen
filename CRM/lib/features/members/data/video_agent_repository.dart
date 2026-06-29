import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/video_agent/data/models/video_agent_models.dart';

/// Repository for the video-agent domain.
///
/// All endpoints are gym-employee-gated; the [ApiClient] attaches the
/// Supabase JWT automatically. Base paths:
/// `GET  /api/v1/gyms/{gymId}/video-spec`
/// `POST /api/v1/gyms/{gymId}/video-agent`
/// `POST /api/v1/gyms/{gymId}/video-agent/refine-from-feed`
///
/// Placed next to [GymContentRepository] per the CRM data-layer convention.
/// Layered per CRM convention:
///   Screen → Bloc → VideoAgentRepository → ApiClient → backend.
class VideoAgentRepository {
  final ApiClient _apiClient;

  VideoAgentRepository(ApiClient apiClient) : _apiClient = apiClient;

  static const String _base = '/api/v1/gyms';

  /// `GET /api/v1/gyms/{gymId}/video-spec`
  ///
  /// Returns null on 404 (no spec has been authored yet).
  /// Throws [ServerException] / [NetworkException] on other failures.
  Future<VideoSpecView?> getConfig(String gymId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '$_base/$gymId/video-spec',
      );
      final data = response.data;
      if (data == null) {
        throw const ServerException('Empty video-spec response');
      }
      return VideoSpecView.fromJson(data);
    } on ServerException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('VideoAgentRepository.getConfig failed', error: e, stackTrace: st);
      throw ServerException('Failed to load video spec: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/video-agent`
  ///
  /// Sends [message] and the full [history] from the previous turn (null on
  /// the first turn). When [acceptedSpec] is provided the backend treats this
  /// as the owner confirming the proposed draft: it saves the spec and returns
  /// `saved: true` with an acknowledgment reply.
  ///
  /// Returns the agent's reply, an optional draft, the updated history, and
  /// whether a save was committed.
  ///
  /// Throws [ServerException] / [NetworkException] on failure.
  Future<AgentTurnResult> agentTurn(
    String gymId,
    String message, {
    List<dynamic>? history,
    Map<String, dynamic>? acceptedSpec,
  }) async {
    try {
      // The backend explicitly accepts `history: null` on the first turn.
      final body = <String, dynamic>{
        'message': message,
        'history': history,
      };
      if (acceptedSpec != null) body['accepted_spec'] = acceptedSpec;
      final response = await _apiClient.post<Map<String, dynamic>>(
        '$_base/$gymId/video-agent',
        data: body,
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
      log('VideoAgentRepository.agentTurn failed', error: e, stackTrace: st);
      throw ServerException('Agent turn failed: $e');
    }
  }

  /// `POST /api/v1/gyms/{gymId}/video-agent/refine-from-feed`
  ///
  /// Refines the spec from recent feed interactions.
  /// Returns null on 404 (nothing new to learn — treat as a no-op).
  /// Throws [ServerException] / [NetworkException] on other failures.
  Future<VideoSpecView?> refineFromFeed(String gymId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '$_base/$gymId/video-agent/refine-from-feed',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty refine response');
      return VideoSpecView.fromJson(data);
    } on ServerException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log(
        'VideoAgentRepository.refineFromFeed failed',
        error: e,
        stackTrace: st,
      );
      throw ServerException('Failed to refine from feed: $e');
    }
  }
}
