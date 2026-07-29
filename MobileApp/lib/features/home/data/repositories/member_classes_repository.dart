import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';

/// Repository for the member's gym schedule board.
///
/// Layered per convention: Bloc → MemberClassesRepository → ApiClient →
/// backend.
class MemberClassesRepository {
  final ApiClient _apiClient;

  MemberClassesRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}/classes`
  /// `?start_date&end_date` → the computed schedule board over the window.
  ///
  /// [startDate] / [endDate] are gym-local ISO dates (`YYYY-MM-DD`). The
  /// response wrapper is `{"items": [...]}`. Throws the typed
  /// [NetworkException] / [ServerException] on failure.
  Future<List<ClassOccurrence>> getBoard({
    required String gymId,
    required String memberId,
    required String startDate,
    required String endDate,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/classes',
        queryParameters: {'start_date': startDate, 'end_date': endDate},
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      final raw = data['items'];
      if (raw is! List) throw const ServerException('Missing items array');
      return raw
          .whereType<Map>()
          .map((e) => ClassOccurrence.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('getBoard failed', error: e, stackTrace: st);
      throw ServerException('Failed to load the class schedule: $e');
    }
  }
}
