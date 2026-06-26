import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// All filters for the members list.
///
/// Each dimension narrows the list independently; the backend
/// AND-combines them. Within [membershipStatus] and [planIds]
/// the values OR together.
class MembersListFilters extends Equatable {
  final List<MembershipStatus> membershipStatus;
  final List<String> planIds;
  final DateRangeFilter? dateRange;
  final String? name;

  const MembersListFilters({
    this.membershipStatus = const [],
    this.planIds = const [],
    this.dateRange,
    this.name,
  });

  factory MembersListFilters.fromJson(
    Map<String, dynamic> json,
  ) {
    return MembersListFilters(
      membershipStatus: (json['membership_status']
                  as List<dynamic>?)
              ?.map(
                (e) =>
                    MembershipStatus.fromJson(e as String),
              )
              .toList() ??
          const [],
      planIds: (json['plan_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      dateRange: json['date_range'] != null
          ? DateRangeFilter.fromJson(
              json['date_range'] as Map<String, dynamic>,
            )
          : null,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'membership_status':
          membershipStatus.map((s) => s.toJson()).toList(),
      'plan_ids': planIds,
      if (dateRange != null)
        'date_range': dateRange!.toJson(),
      if (name != null) 'name': name,
    };
  }

  MembersListFilters copyWith({
    List<MembershipStatus>? membershipStatus,
    List<String>? planIds,
    DateRangeFilter? dateRange,
    bool clearDateRange = false,
    String? name,
    bool clearName = false,
  }) {
    return MembersListFilters(
      membershipStatus:
          membershipStatus ?? this.membershipStatus,
      planIds: planIds ?? this.planIds,
      dateRange: clearDateRange
          ? null
          : dateRange ?? this.dateRange,
      name: clearName ? null : name ?? this.name,
    );
  }

  /// Whether any filter dimension is currently active.
  bool get hasActiveFilters =>
      membershipStatus.isNotEmpty ||
      planIds.isNotEmpty ||
      dateRange != null ||
      (name != null && name!.isNotEmpty);

  @override
  List<Object?> get props => [
        membershipStatus,
        planIds,
        dateRange,
        name,
      ];
}
