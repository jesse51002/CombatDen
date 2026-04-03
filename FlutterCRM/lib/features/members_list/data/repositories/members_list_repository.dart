import 'package:crm/core/network/api_client.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';

/// Repository for the CRM members list screen.
///
/// Provides access to the members list and total counts
/// endpoints via [ApiClient].
class MembersListRepository {
  final ApiClient _apiClient;

  MembersListRepository({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  /// Fetches a filtered, sorted, paginated list of gym
  /// members.
  Future<CrmMembersListResponse> getMembersList(
    CrmMembersListRequest request,
  ) async {
    final response = await _apiClient.post(
      '/api/v1/members/crm_members_list',
      data: request.toJson(),
    );
    return CrmMembersListResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Fetches unfiltered member counts per status.
  Future<MembersListTotalCounts> getTotalCounts(
    String gymId,
  ) async {
    final response = await _apiClient.get(
      '/api/v1/members/crm_total_counts',
      queryParameters: {'gym_id': gymId},
    );
    return MembersListTotalCounts.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}
