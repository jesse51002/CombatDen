import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/profile/data/models/member_rank_progress.dart';

/// Repository for the member's rank-progress series — the data behind the
/// profile's rank graph.
///
/// Layered per convention: Bloc → MemberRankProgressRepository → ApiClient →
/// backend. Scoped to the selected member; the bloc threads `gymId` +
/// `memberId` from the SelectedMember global.
class MemberRankProgressRepository {
  final ApiClient _apiClient;

  MemberRankProgressRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/rank-progress` → the
  /// member's [MemberRankProgress] series. An empty `points` is a valid 200
  /// (no rank / ranks disabled). Throws the typed [NetworkException] /
  /// [ServerException] on failure.
  Future<MemberRankProgress> getRankProgress({
    required String gymId,
    required String memberId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/rank-progress',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return MemberRankProgress.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('getRankProgress failed', error: e, stackTrace: st);
      throw ServerException('Failed to load your rank progress: $e');
    }
  }
}
