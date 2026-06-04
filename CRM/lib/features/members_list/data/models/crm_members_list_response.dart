import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// Response for the CRM members list endpoint.
///
/// Uses a hand-written [fromJson] to dispatch the
/// polymorphic [data] rows based on the [view]
/// discriminator field.
class CrmMembersListResponse extends Equatable {
  final MembersListView view;
  final MembersListFilters filters;
  final List<MemberRow> data;

  const CrmMembersListResponse({
    required this.view,
    required this.filters,
    required this.data,
  });

  factory CrmMembersListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final view = MembersListView.fromJson(
      json['view'] as String,
    );
    final filters = MembersListFilters.fromJson(
      json['filters'] as Map<String, dynamic>,
    );
    final data = (json['data'] as List<dynamic>)
        .map(
          (e) => MemberRow.fromJson(
            e as Map<String, dynamic>,
            view,
          ),
        )
        .toList();
    return CrmMembersListResponse(
      view: view,
      filters: filters,
      data: data,
    );
  }

  @override
  List<Object?> get props => [view, filters, data];
}
