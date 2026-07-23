import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/members/presentation/dialogs/members_list_filter_date_field.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/multi_select_pills.dart';

/// Statuses offered in the filter dialog. The resilient
/// [MembershipStatus.unknown] fallback is never user-pickable.
const _statusOptions = <MembershipStatus>[
  MembershipStatus.active,
  MembershipStatus.trial,
  MembershipStatus.frozen,
  MembershipStatus.overdue,
  MembershipStatus.dormant,
  MembershipStatus.cancelled,
  MembershipStatus.ended,
  MembershipStatus.noMembership,
];

/// The body of the members filter dialog: the status, membership-plan,
/// and start-date sections. Stateless — the selection state and the
/// apply / clear logic live on the dialog's State.
class MembersListFilterSections extends StatelessWidget {
  final Set<MembershipStatus> statuses;
  final List<MembershipPlanResponse> plans;
  final Set<String> planIds;
  final List<MainRank> ranks;
  final Set<String> rankIds;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<MembershipStatus> onToggleStatus;
  final ValueChanged<String> onTogglePlan;
  final ValueChanged<String> onToggleRank;
  final void Function(DateTime? start, DateTime? end) onDatesChanged;

  const MembersListFilterSections({
    super.key,
    required this.statuses,
    required this.plans,
    required this.planIds,
    required this.ranks,
    required this.rankIds,
    required this.startDate,
    required this.endDate,
    required this.onToggleStatus,
    required this.onTogglePlan,
    required this.onToggleRank,
    required this.onDatesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        _Section(
          title: 'Membership status',
          child: MultiSelectPills(
            labels:
                _statusOptions.map((s) => s.displayLabel).toList(),
            selectedIndices: {
              for (var i = 0; i < _statusOptions.length; i++)
                if (statuses.contains(_statusOptions[i])) i,
            },
            onToggled: (i) => onToggleStatus(_statusOptions[i]),
          ),
        ),
        if (plans.isNotEmpty)
          _Section(
            title: 'Membership',
            child: MultiSelectPills(
              labels: plans.map((p) => p.planName).toList(),
              selectedIndices: {
                for (var i = 0; i < plans.length; i++)
                  if (planIds.contains(plans[i].planId)) i,
              },
              onToggled: (i) => onTogglePlan(plans[i].planId),
            ),
          ),
        if (ranks.isNotEmpty)
          _Section(
            title: 'Rank',
            child: MultiSelectPills(
              labels: ranks.map((r) => r.name).toList(),
              selectedIndices: {
                for (var i = 0; i < ranks.length; i++)
                  if (rankIds.contains(ranks[i].rankId)) i,
              },
              onToggled: (i) => onToggleRank(ranks[i].rankId),
            ),
          ),
        _Section(
          title: 'Start date',
          child: MembersListFilterDateField(
            startDate: startDate,
            endDate: endDate,
            onChanged: onDatesChanged,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          title,
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        child,
      ],
    );
  }
}
