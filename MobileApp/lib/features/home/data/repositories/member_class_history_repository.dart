import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';

/// Repository for the member's class history — open reservations plus a
/// paginated attended / no-show feed.
///
/// Layered per convention: Bloc → MemberClassHistoryRepository → ApiClient →
/// backend.
class MemberClassHistoryRepository {
  final ApiClient _apiClient;

  MemberClassHistoryRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/class-history`
  /// `?limit&offset` → the member's [MemberClassHistory] (open reservations +
  /// a page of history). Throws the typed [NetworkException] /
  /// [ServerException] on failure.
  Future<MemberClassHistory> getHistory({
    required String gymId,
    required String memberId,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/class-history',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return MemberClassHistory.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('getHistory failed', error: e, stackTrace: st);
      throw ServerException('Failed to load your class history: $e');
    }
  }
}
