import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_contact_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_last_class_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_name_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_status_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/simple_text_cell.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Members table driven by live [MemberRow] data from the
/// bloc. Columns vary per [activeView].
///
/// Tapping a row pushes [MemberDetailScreen] for that member.
class MembersTable extends StatelessWidget {
  final MembersListView activeView;
  final List<MemberRow> members;
  final String gymId;
  final bool isLoadingMore;
  final bool hasReachedEnd;
  final VoidCallback onLoadMore;

  /// Whether any filter (status / plan / date / search) is active.
  /// Drives the empty state's "try removing filters" hint.
  final bool hasActiveFilters;

  const MembersTable({
    super.key,
    required this.activeView,
    required this.members,
    required this.gymId,
    required this.isLoadingMore,
    required this.hasReachedEnd,
    required this.onLoadMore,
    this.hasActiveFilters = false,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty && !isLoadingMore) {
      return _emptyState();
    }

    return AppDataTable(
      infiniteScroll: !hasReachedEnd,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      columns: _columns(),
      rows: members.map((row) {
        return AppDataTableRow(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                // Name the route with the member id so the URL becomes
                // `/members/detail/<id>` and a reload restores this member.
                settings: RouteSettings(
                  name: AppRoutes.memberDetailPath(row.memberId),
                ),
                builder: (_) => MemberDetailScreen(
                  memberId: row.memberId,
                  gymId: gymId,
                ),
              ),
            );
          },
          cells: _cellsForRow(row, context),
        );
      }).toList(),
    );
  }

  List<AppDataTableColumn> _columns() {
    return switch (activeView) {
      MembersListView.all => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 180,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Contact',
            minWidth: 200,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Membership',
            minWidth: 220,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Last Class',
            minWidth: 130,
          ),
        ],
      MembersListView.trial => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 180,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Days Remaining',
            minWidth: 140,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Trial Start Date',
            minWidth: 140,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Trial End Date',
            minWidth: 140,
            fill: true,
          ),
        ],
      MembersListView.frozen => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 180,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Freeze Start',
            minWidth: 140,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Freeze End',
            minWidth: 140,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Days Until Unfrozen',
            minWidth: 160,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Price',
            minWidth: 120,
          ),
        ],
      MembersListView.overdue => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 180,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Contact',
            minWidth: 200,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Membership',
            minWidth: 200,
            fill: true,
          ),
          AppDataTableColumn(
            label: 'Days Late',
            minWidth: 120,
          ),
        ],
    };
  }

  List<Widget> _cellsForRow(
    MemberRow row,
    BuildContext context,
  ) {
    return switch (row) {
      AllViewRow r => [
          MemberNameCell(name: r.name, avatarUrl: r.avatarUrl),
          MemberContactCell(email: r.email),
          MemberStatusCell(
            status: r.membershipStatus,
            text: r.membershipText,
          ),
          MemberLastClassCell(
            daysAgo: r.daysSinceLastClass,
          ),
        ],
      TrialViewRow r => [
          MemberNameCell(name: r.name, avatarUrl: r.avatarUrl),
          SimpleTextCell(
            text: r.daysRemaining < 0
                ? 'Ended ${r.daysRemaining.abs()} days ago'
                : '${r.daysRemaining} days left',
            color: r.daysRemaining < 0
                ? DesignConstants.badRed
                : r.daysRemaining <= 2
                    ? DesignConstants.okYellow
                    : DesignConstants.goodGreen,
          ),
          SimpleTextCell(text: r.startDate),
          SimpleTextCell(text: r.endDate),
        ],
      FrozenViewRow r => [
          MemberNameCell(name: r.name, avatarUrl: r.avatarUrl),
          SimpleTextCell(text: r.freezeStart),
          SimpleTextCell(text: r.freezeEnd),
          SimpleTextCell(
            text: r.daysUntilUnfrozen < 0
                ? 'Unfroze ${-r.daysUntilUnfrozen} days ago'
                : '${r.daysUntilUnfrozen} days',
            color: r.daysUntilUnfrozen <= 6
                ? DesignConstants.goodGreen
                : DesignConstants.okYellow,
          ),
          SimpleTextCell(text: r.price),
        ],
      OverdueViewRow r => [
          MemberNameCell(name: r.name, avatarUrl: r.avatarUrl),
          MemberContactCell(email: r.email),
          SimpleTextCell(text: r.membershipText),
          SimpleTextCell(
            text: '${r.daysLate} days',
            color: DesignConstants.badRed,
          ),
        ],
    };
  }

  Widget _emptyState() {
    // With a filter active, zero rows means "nothing matched" — point
    // at the filters. Otherwise it's a genuinely empty view.
    final headline = hasActiveFilters
        ? 'No members match your filters'
        : switch (activeView) {
            MembersListView.all => 'No members yet',
            MembersListView.trial => 'No trial members',
            MembersListView.frozen => 'No frozen members',
            MembersListView.overdue => 'No overdue members',
          };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          Icon(
            Symbols.people_sharp,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                headline,
                textAlign: TextAlign.center,
                style: DesignConstants.h2.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              if (hasActiveFilters)
                Text(
                  'Try removing filters to see more.',
                  textAlign: TextAlign.center,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
