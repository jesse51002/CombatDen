import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/members/presentation/dialogs/members_list_filter_date_field.dart';
import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/filter_pills.dart';

/// Statuses offered in the filter dialog. The resilient
/// [MembershipStatus.unknown] fallback is never user-pickable.
const _statusOptions = <MembershipStatus>[
  MembershipStatus.active,
  MembershipStatus.trial,
  MembershipStatus.frozen,
  MembershipStatus.overdue,
  MembershipStatus.cancelled,
  MembershipStatus.ended,
  MembershipStatus.noMembership,
];

/// The "Add filter" dialog for the members list: pick membership
/// statuses, membership plans, and a start-date range. Returns the
/// updated [MembersListFilters] on Apply (the name/search filter is
/// preserved), or null if dismissed.
class MembersListFilterDialog extends StatefulWidget {
  final MembersListFilters initial;
  final List<MembershipPlanResponse> plans;

  const MembersListFilterDialog({
    super.key,
    required this.initial,
    required this.plans,
  });

  static Future<MembersListFilters?> show({
    required BuildContext context,
    required MembersListFilters initial,
    required List<MembershipPlanResponse> plans,
  }) {
    return showDialog<MembersListFilters>(
      context: context,
      builder: (_) => MembersListFilterDialog(
        initial: initial,
        plans: plans,
      ),
    );
  }

  @override
  State<MembersListFilterDialog> createState() =>
      _MembersListFilterDialogState();
}

class _MembersListFilterDialogState
    extends State<MembersListFilterDialog> {
  late Set<MembershipStatus> _statuses;
  late Set<String> _planIds;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _statuses = widget.initial.membershipStatus.toSet();
    _planIds = widget.initial.planIds.toSet();
    _startDate = _parse(widget.initial.dateRange?.startDate);
    _endDate = _parse(widget.initial.dateRange?.endDate);
  }

  DateTime? _parse(String? iso) =>
      iso == null ? null : DateTime.tryParse(iso);

  void _toggleStatus(MembershipStatus s) {
    setState(() {
      if (!_statuses.remove(s)) _statuses.add(s);
    });
  }

  void _togglePlan(String id) {
    setState(() {
      if (!_planIds.remove(id)) _planIds.add(id);
    });
  }

  void _clearAll() {
    setState(() {
      _statuses = {};
      _planIds = {};
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    final fmt = DateFormat('yyyy-MM-dd');
    final hasDates = _startDate != null || _endDate != null;
    Navigator.of(context).pop(
      widget.initial.copyWith(
        membershipStatus: _statuses.toList(),
        planIds: _planIds.toList(),
        dateRange: hasDates
            ? DateRangeFilter(
                startDate: _startDate == null
                    ? null
                    : fmt.format(_startDate!),
                endDate: _endDate == null
                    ? null
                    : fmt.format(_endDate!),
              )
            : null,
        clearDateRange: !hasDates,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Filter members',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          _Section(
            title: 'Membership status',
            child: MultiSelectPills(
              labels: _statusOptions
                  .map((s) => s.displayLabel)
                  .toList(),
              selectedIndices: {
                for (var i = 0; i < _statusOptions.length; i++)
                  if (_statuses.contains(_statusOptions[i])) i,
              },
              onToggled: (i) => _toggleStatus(_statusOptions[i]),
            ),
          ),
          if (widget.plans.isNotEmpty)
            _Section(
              title: 'Membership',
              child: MultiSelectPills(
                labels: widget.plans
                    .map((p) => p.planName)
                    .toList(),
                selectedIndices: {
                  for (var i = 0; i < widget.plans.length; i++)
                    if (_planIds.contains(widget.plans[i].planId)) i,
                },
                onToggled: (i) =>
                    _togglePlan(widget.plans[i].planId),
              ),
            ),
          _Section(
            title: 'Start date',
            child: MembersListFilterDateField(
              startDate: _startDate,
              endDate: _endDate,
              onChanged: (start, end) => setState(() {
                _startDate = start;
                _endDate = end;
              }),
            ),
          ),
        ],
      ),
      actions: AppDialogActions(
        secondaryLabel: 'Clear all',
        secondaryOnPressed: _clearAll,
        primaryLabel: 'Apply',
        primaryOnPressed: _apply,
      ),
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
