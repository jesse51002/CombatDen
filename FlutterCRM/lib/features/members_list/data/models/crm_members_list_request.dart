import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// Request body for the CRM members list endpoint.
class CrmMembersListRequest extends Equatable {
  final String gymId;
  final MembersListView prevView;
  final MembersListView requestedView;
  final MembersListFilters filters;
  final int startIndex;
  final int count;

  const CrmMembersListRequest({
    required this.gymId,
    required this.prevView,
    required this.requestedView,
    this.filters = const MembersListFilters(),
    this.startIndex = 0,
    this.count = 25,
  });

  Map<String, dynamic> toJson() {
    return {
      'gym_id': gymId,
      'prev_view': prevView.toJson(),
      'requested_view': requestedView.toJson(),
      'filters': filters.toJson(),
      'start_index': startIndex,
      'count': count,
    };
  }

  @override
  List<Object?> get props => [
        gymId,
        prevView,
        requestedView,
        filters,
        startIndex,
        count,
      ];
}
