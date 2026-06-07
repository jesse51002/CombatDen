import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// All filters for the members list.
class MembersListFilters extends Equatable {
  final List<MembershipStatus> membershipStatus;
  final DateRangeFilter? dateRange;
  final String? name;

  const MembersListFilters({
    this.membershipStatus = const [],
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
      if (dateRange != null)
        'date_range': dateRange!.toJson(),
      if (name != null) 'name': name,
    };
  }

  MembersListFilters copyWith({
    List<MembershipStatus>? membershipStatus,
    DateRangeFilter? dateRange,
    bool clearDateRange = false,
    String? name,
    bool clearName = false,
  }) {
    return MembersListFilters(
      membershipStatus:
          membershipStatus ?? this.membershipStatus,
      dateRange: clearDateRange
          ? null
          : dateRange ?? this.dateRange,
      name: clearName ? null : name ?? this.name,
    );
  }

  @override
  List<Object?> get props => [
        membershipStatus,
        dateRange,
        name,
      ];
}
