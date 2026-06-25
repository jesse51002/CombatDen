import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// Request body for the CRM members list endpoint.
///
/// Attributes:
///   gymId: The gym to list members for.
///   view: The view to show (decides the row shape). The view
///     and the filters are independent — the backend applies
///     both as given and does not reconcile one against the
///     other.
///   filters: Active filters from the frontend.
///   startIndex: Pagination offset.
///   count: Number of rows to fetch per page.
class CrmMembersListRequest extends Equatable {
  final String gymId;
  final MembersListView view;
  final MembersListFilters filters;
  final int startIndex;
  final int count;

  const CrmMembersListRequest({
    required this.gymId,
    required this.view,
    this.filters = const MembersListFilters(),
    this.startIndex = 0,
    this.count = 25,
  });

  Map<String, dynamic> toJson() {
    return {
      'gym_id': gymId,
      'view': view.toJson(),
      'filters': filters.toJson(),
      'start_index': startIndex,
      'count': count,
    };
  }

  @override
  List<Object?> get props => [
        gymId,
        view,
        filters,
        startIndex,
        count,
      ];
}
