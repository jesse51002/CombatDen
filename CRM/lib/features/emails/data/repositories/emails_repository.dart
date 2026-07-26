import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/emails/data/models/email_kind.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// Repository for CombatDen's own transactional / marketing email over the
/// FastAPI `emails` domain via [ApiClient]. Paths and shapes match
/// `../FastApiBackend/src/emails/schema/emails_schema.py`.
///
/// Only the manual (re)send is exposed — every other send is automatic, fired
/// by the backend as a side effect of a create. The request carries IDs only
/// (never an address): the backend resolves the address from the subject's own
/// row, so this can never mail an arbitrary address.
class EmailsRepository {
  final ApiClient _apiClient;

  EmailsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// `POST /api/v1/emails/send` — (re)send [kind] to the named subject.
  ///
  /// Exactly one of [employeeId] / [memberId] is meaningful, decided by
  /// [kind]: `staff_onboarding` needs the employee, `member_app_invite` the
  /// member. Returns the response's `outcome` — the honest answer the caller
  /// renders, never an assumed success.
  ///
  /// Throws [InviteRateLimitedException] on the backend's 429 (three sends of
  /// this kind to this subject in the trailing hour), so a caller shows the
  /// real reason instead of a generic failure.
  Future<InviteOutcome> sendEmail({
    required String gymId,
    required EmailKind kind,
    String? employeeId,
    String? memberId,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/emails/send',
        data: <String, dynamic>{
          'gym_id': gymId,
          'kind': kind.value,
          if (employeeId != null) 'employee_id': employeeId,
          if (memberId != null) 'member_id': memberId,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return InviteOutcome.fromJson(data['outcome'] as String);
    } on ServerException catch (e) {
      if (e.statusCode == 429) throw const InviteRateLimitedException();
      rethrow;
    }
  }
}
