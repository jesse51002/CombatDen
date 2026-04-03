import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository for member data access.
///
/// Uses [ApiClient] for backend API calls and
/// [SupabaseClient] for direct database queries.
class MemberRepository {
  final ApiClient _apiClient;
  final SupabaseClient _supabase;

  MemberRepository({
    required ApiClient apiClient,
    required SupabaseClient supabase,
  })  : _apiClient = apiClient,
        _supabase = supabase;

  /// Fetches full member detail from the backend API.
  Future<MemberDetailResponse> getMemberDetail(
    String crmUserId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/members/member_details',
      queryParameters: {'crm_user_id': crmUserId},
    );
    return MemberDetailResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Fetches all members for the sidebar quick-list.
  Future<List<MemberSummary>> getAllMembers() async {
    final response = await _supabase
        .from('user_gym_profiles')
        .select(
          'crm_user_id, first_name, last_name, photo_url',
        )
        .order('first_name');

    return (response as List<dynamic>)
        .map(
          (e) => MemberSummary.fromJson(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}
