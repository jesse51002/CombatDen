import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/home/data/models/signup_result.dart';

/// Repository for a member's own class reservations (sign-ups).
///
/// Layered per convention: Bloc → MemberSignupRepository → ApiClient → backend.
///
/// Both calls address an occurrence by its ORIGINAL slot
/// `(class_id, occurrence_date, occurrence_time)` — the caller passes the
/// board occurrence's `original_date` / `original_time` VERBATIM (never
/// device-tz shifted), so the backend resolves the exact slot.
class MemberSignupRepository {
  final ApiClient _apiClient;

  MemberSignupRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `POST /api/v1/member/gyms/{gymId}/members/{memberId}/signup` — reserve a
  /// spot. Body `{class_id, occurrence_date, occurrence_time}` mirrors
  /// `MemberPortalSignupRequest`. A repeat returns the existing sign-up with
  /// `already_signed_up = true` (still a 200). A full / deleted / non-occurrence
  /// class comes back as a 400 [ServerException] carrying the backend `detail`.
  Future<SignupResult> reserve({
    required String gymId,
    required String memberId,
    required String classId,
    required String occurrenceDate,
    required String occurrenceTime,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/signup',
        data: {
          'class_id': classId,
          'occurrence_date': occurrenceDate,
          'occurrence_time': occurrenceTime,
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return SignupResult.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('reserve failed', error: e, stackTrace: st);
      throw ServerException('Failed to reserve your spot: $e');
    }
  }

  /// `DELETE /api/v1/member/gyms/{gymId}/members/{memberId}/signup` — cancel a
  /// reservation. The three slot fields go as QUERY params. Returns
  /// `removed = false` (still a 200) when there was no reservation.
  Future<SignupRemoveResult> cancel({
    required String gymId,
    required String memberId,
    required String classId,
    required String occurrenceDate,
    required String occurrenceTime,
  }) async {
    try {
      final response = await _apiClient.delete<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId/signup',
        queryParameters: {
          'class_id': classId,
          'occurrence_date': occurrenceDate,
          'occurrence_time': occurrenceTime,
        },
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return SignupRemoveResult.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('cancel failed', error: e, stackTrace: st);
      throw ServerException('Failed to cancel your reservation: $e');
    }
  }
}
