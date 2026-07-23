import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';

/// Repository for the member's own profile — the shared source behind the
/// topbar's streak / points and (later) the rank block.
///
/// Layered per convention: Bloc → MemberProfileRepository → ApiClient →
/// backend.
class MemberProfileRepository {
  final ApiClient _apiClient;

  MemberProfileRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/gyms/{gymId}/members/{memberId}` → the member's
  /// [MemberProfile]. Throws the typed [NetworkException] / [ServerException]
  /// on failure.
  Future<MemberProfile> getProfile({
    required String gymId,
    required String memberId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/gyms/$gymId/members/$memberId',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      return MemberProfile.fromJson(data);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('getProfile failed', error: e, stackTrace: st);
      throw ServerException('Failed to load your profile: $e');
    }
  }
}
