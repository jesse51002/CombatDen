import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/members/presentation/dialogs/members_list_filter_sections.dart';
import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// The "Add filter" dialog for the members list: pick membership
/// statuses, membership plans, and a start-date range. Returns the
/// updated [MembersListFilters] on Apply (the name/search filter is
/// preserved), or null if dismissed.
class MembersListFilterDialog extends StatefulWidget {
  final MembersListFilters initial;
  final List<MembershipPlanResponse> plans;
  final List<MainRank> ranks;

  const MembersListFilterDialog({
    super.key,
    required this.initial,
    required this.plans,
    required this.ranks,
  });

  static Future<MembersListFilters?> show({
    required BuildContext context,
    required MembersListFilters initial,
    required List<MembershipPlanResponse> plans,
    required List<MainRank> ranks,
  }) {
    return showDialog<MembersListFilters>(
      context: context,
      builder: (_) => MembersListFilterDialog(
        initial: initial,
        plans: plans,
        ranks: ranks,
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
  late Set<String> _rankIds;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _statuses = widget.initial.membershipStatus.toSet();
    _planIds = widget.initial.planIds.toSet();
    _rankIds = widget.initial.rankIds.toSet();
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

  void _toggleRank(String id) {
    setState(() {
      if (!_rankIds.remove(id)) _rankIds.add(id);
    });
  }

  void _clearAll() {
    setState(() {
      _statuses = {};
      _planIds = {};
      _rankIds = {};
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
        rankIds: _rankIds.toList(),
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
      body: MembersListFilterSections(
        statuses: _statuses,
        plans: widget.plans,
        planIds: _planIds,
        ranks: widget.ranks,
        rankIds: _rankIds,
        startDate: _startDate,
        endDate: _endDate,
        onToggleStatus: _toggleStatus,
        onTogglePlan: _togglePlan,
        onToggleRank: _toggleRank,
        onDatesChanged: (start, end) => setState(() {
          _startDate = start;
          _endDate = end;
        }),
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
