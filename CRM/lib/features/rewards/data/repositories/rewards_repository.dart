import 'dart:developer';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/rewards/data/models/pending_redemption_list_response.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';

/// Repository for the rewards domain.
///
/// Wraps [ApiClient] for the gym reward catalog CRUD and the admin
/// redemption approval queue.
///
/// Layered per CRM convention:
///   Screen → Bloc → RewardsRepository → ApiClient → backend.
class RewardsRepository {
  final ApiClient _apiClient;

  RewardsRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/rewards/?gym_id=<uuid>&include_inactive=<bool>`
  Future<List<RewardResponse>> listRewards(
    String gymId, {
    bool includeInactive = false,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/rewards/',
        queryParameters: {
          'gym_id': gymId,
          'include_inactive': includeInactive,
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      final raw = data['items'];
      if (raw is! List) throw const ServerException('Missing items array');
      return raw
          .whereType<Map>()
          .map((e) => RewardResponse.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('listRewards failed', error: e, stackTrace: st);
      throw ServerException('Failed to load rewards: $e');
    }
  }

  /// `POST /api/v1/rewards/`
  Future<RewardResponse> createReward({
    required String gymId,
    required String title,
    required int pointCost,
    String? priceLabel,
    String? imageUrl,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/rewards/',
        data: {
          'gym_id': gymId,
          'title': title,
          'point_cost': pointCost,
          if (priceLabel != null && priceLabel.isNotEmpty)
            'price_label': priceLabel,
          'image_url': ?imageUrl,
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return RewardResponse.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('createReward failed', error: e, stackTrace: st);
      throw ServerException('Failed to create reward: $e');
    }
  }

  /// `PUT /api/v1/rewards/{reward_id}`
  Future<RewardResponse> updateReward(
    String rewardId, {
    String? title,
    int? pointCost,
    String? priceLabel,
    String? imageUrl,
    bool? isActive,
  }) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/rewards/$rewardId',
        data: {
          'data': {
            'title': ?title,
            'point_cost': ?pointCost,
            'price_label': ?priceLabel,
            'image_url': ?imageUrl,
            'is_active': ?isActive,
          },
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return RewardResponse.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('updateReward failed', error: e, stackTrace: st);
      throw ServerException('Failed to update reward: $e');
    }
  }

  /// `DELETE /api/v1/rewards/{reward_id}` — soft-deletes (sets is_active=false).
  Future<void> deleteReward(String rewardId) async {
    try {
      await _apiClient.delete<dynamic>('/api/v1/rewards/$rewardId');
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('deleteReward failed', error: e, stackTrace: st);
      throw ServerException('Failed to remove reward: $e');
    }
  }

  /// `GET /api/v1/rewards/redemptions/pending?gym_id=<uuid>`
  ///
  /// The backend paginates (default first page) and returns a `total`
  /// count on the list response; the CRM keeps fetching the default page
  /// (no load-more UI yet) but parses `total` off the response.
  Future<PendingRedemptionListResponse> listPending(String gymId) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/rewards/redemptions/pending',
        queryParameters: {'gym_id': gymId},
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      if (data['items'] is! List) {
        throw const ServerException('Missing items array');
      }
      return PendingRedemptionListResponse.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('listPending failed', error: e, stackTrace: st);
      throw ServerException('Failed to load pending redemptions: $e');
    }
  }

  /// `POST /api/v1/rewards/redemptions/{redemption_id}/approve`
  ///
  /// Throws [RedemptionAlreadyDecidedException] on HTTP 409.
  Future<void> approve(String redemptionId) async {
    try {
      await _apiClient.post<dynamic>(
        '/api/v1/rewards/redemptions/$redemptionId/approve',
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw const RedemptionAlreadyDecidedException();
      }
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('approve failed', error: e, stackTrace: st);
      throw ServerException('Failed to approve redemption: $e');
    }
  }

  /// `POST /api/v1/rewards/redemptions/{redemption_id}/reject`
  ///
  /// Throws [RedemptionAlreadyDecidedException] on HTTP 409.
  Future<void> reject(String redemptionId) async {
    try {
      await _apiClient.post<dynamic>(
        '/api/v1/rewards/redemptions/$redemptionId/reject',
      );
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        throw const RedemptionAlreadyDecidedException();
      }
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('reject failed', error: e, stackTrace: st);
      throw ServerException('Failed to reject redemption: $e');
    }
  }
}
