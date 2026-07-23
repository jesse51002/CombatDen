import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/rewards/data/models/redeem_result.dart';
import 'package:mobile_app/features/rewards/data/models/redemption_record.dart';
import 'package:mobile_app/features/rewards/data/models/reward_item.dart';

/// Repository for the member's rewards surface — the gym's active catalog, the
/// member's own redemption history, and requesting a redemption.
///
/// Layered per convention: Bloc → MemberRewardsRepository → ApiClient →
/// backend. Every route is scoped to the selected member; the bloc threads
/// `gymId` + `memberId` from the SelectedMember global.
class MemberRewardsRepository {
  final ApiClient _apiClient;

  MemberRewardsRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/rewards` → the gym's
  /// ACTIVE reward catalog (cheapest first). The response wrapper is
  /// `{"items": [...]}` (`RewardListResponse`).
  Future<List<RewardItem>> listCatalog({
    required String gymId,
    required String memberId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/rewards',
      );
      return _items(response.data, RewardItem.fromJson);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('listCatalog failed', error: e, stackTrace: st);
      throw ServerException('Failed to load rewards: $e');
    }
  }

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/redemptions` → the
  /// member's own redemption history, newest first
  /// (`RedemptionHistoryResponse`, `{"items": [...]}`).
  Future<List<RedemptionRecord>> listRedemptions({
    required String gymId,
    required String memberId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/redemptions',
      );
      return _items(response.data, RedemptionRecord.fromJson);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('listRedemptions failed', error: e, stackTrace: st);
      throw ServerException('Failed to load your redemptions: $e');
    }
  }

  /// `POST /api/v1/member/gyms/{gymId}/members/{memberId}/rewards/{rewardId}/redeem`
  /// — atomically debit the member's points and record a PENDING redemption
  /// (`auto_approve` hardwired false server-side). No body: the member is in
  /// the path. Returns the created [RedeemResult] (201). Insufficient points /
  /// an inactive reward come back as a 400 [ServerException] carrying the
  /// backend `detail`.
  Future<RedeemResult> redeem({
    required String gymId,
    required String memberId,
    required String rewardId,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/rewards/$rewardId/redeem',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return RedeemResult.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('redeem failed', error: e, stackTrace: st);
      throw ServerException('Failed to redeem the reward: $e');
    }
  }

  /// Parse a `{"items": [...]}` list envelope into typed models.
  List<T> _items<T>(
    Map<String, dynamic>? data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (data == null) throw const ServerException('Empty response');
    final raw = data['items'];
    if (raw is! List) throw const ServerException('Missing items array');
    return raw
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}
