import 'dart:developer';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';

/// Repository for the member-portal identity surface.
///
/// Layered per convention: Screen → Bloc/Gate → MemberPortalRepository →
/// ApiClient → backend.
class MemberPortalRepository {
  final ApiClient _apiClient;

  MemberPortalRepository({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// `GET /api/v1/member/members` — the caller's member rows across gyms.
  ///
  /// The response wrapper is `{"members": [...]}` (`members.email` is
  /// non-unique by design, so this is always a list). Throws the typed
  /// [NetworkException] / [ServerException] on failure so the gate can tell an
  /// offline failure apart from an empty (but reachable) result.
  Future<List<MemberIdentity>> getMyMembers() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/member/members',
      );
      final data = response.data;
      if (data == null) throw const ServerException('Empty response');
      final raw = data['members'];
      if (raw is! List) throw const ServerException('Missing members array');
      return raw
          .whereType<Map>()
          .map((e) => MemberIdentity.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on ServerException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e, st) {
      log('getMyMembers failed', error: e, stackTrace: st);
      throw ServerException('Failed to load your memberships: $e');
    }
  }
}
