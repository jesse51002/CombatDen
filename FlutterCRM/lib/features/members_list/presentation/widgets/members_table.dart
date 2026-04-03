import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/presentation/widgets/cells/contact_cell.dart';
import 'package:crm/features/members_list/presentation/widgets/cells/last_class_indicator.dart';
import 'package:crm/features/members_list/presentation/widgets/cells/membership_badge.dart';
import 'package:crm/features/members_list/presentation/widgets/cells/name_cell.dart';
import 'package:crm/features/members_list/presentation/widgets/cells/simple_text_cell.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Orchestrates the AppDataTable per active view.
///
/// Selects the correct column definitions and cell
/// builders based on the active [MembersListView].
class MembersTable extends StatelessWidget {
  final MembersListView activeView;
  final List<MemberRow> rows;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;
  final void Function(String crmUserId) onRowTap;

  const MembersTable({
    super.key,
    required this.activeView,
    required this.rows,
    this.isLoadingMore = false,
    this.onLoadMore,
    required this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && !isLoadingMore) {
      return _emptyState();
    }

    return AppDataTable(
      columns: _columns(),
      rows: _buildRows(),
      infiniteScroll: true,
      onLoadMore: onLoadMore,
      isLoadingMore: isLoadingMore,
    );
  }

  List<AppDataTableColumn> _columns() {
    return switch (activeView) {
      MembersListView.all => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 150,
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
            minWidth: 120,
            fill: true,
          ),
        ],
      MembersListView.trial => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 150,
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
            minWidth: 150,
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
            fill: true,
          ),
        ],
      MembersListView.overdue => const [
          AppDataTableColumn(
            label: 'Name',
            minWidth: 150,
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

  List<AppDataTableRow> _buildRows() {
    return rows.map((row) {
      return AppDataTableRow(
        cells: _cellsForRow(row),
        onTap: () => onRowTap(row.crmUserId),
      );
    }).toList();
  }

  List<Widget> _cellsForRow(MemberRow row) {
    return switch (row) {
      AllViewRow r => [
          NameCell(
            name: r.name,
            avatarUrl: r.avatarUrl,
          ),
          ContactCell(email: r.email),
          MembershipBadge(
            status: r.membershipStatus,
            text: r.membershipText,
          ),
          LastClassIndicator(
            daysSinceLastClass:
                r.daysSinceLastClass,
          ),
        ],
      TrialViewRow r => [
          NameCell(
            name: r.name,
            avatarUrl: r.avatarUrl,
          ),
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
          NameCell(
            name: r.name,
            avatarUrl: r.avatarUrl,
          ),
          SimpleTextCell(text: r.freezeStart),
          SimpleTextCell(text: r.freezeEnd),
          SimpleTextCell(
            text: r.daysUntilUnfrozen < 0
                ? 'Unfroze ${-r.daysUntilUnfrozen} '
                    'days ago'
                : '${r.daysUntilUnfrozen} days',
            color: r.daysUntilUnfrozen < 0
                ? DesignConstants.goodGreen
                : r.daysUntilUnfrozen < 7
                    ? DesignConstants.goodGreen
                    : DesignConstants.okYellow,
          ),
          SimpleTextCell(text: r.price),
        ],
      OverdueViewRow r => [
          NameCell(
            name: r.name,
            avatarUrl: r.avatarUrl,
          ),
          ContactCell(email: r.email),
          SimpleTextCell(text: r.membershipText),
          SimpleTextCell(
            text: '${r.daysLate} days',
            color: DesignConstants.badRed,
          ),
        ],
    };
  }

  Widget _emptyState() {
    final message = switch (activeView) {
      MembersListView.all => 'No members yet',
      MembersListView.trial =>
        'No trial members',
      MembersListView.frozen =>
        'No frozen members',
      MembersListView.overdue =>
        'No overdue members',
    };

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Symbols.people_sharp,
            size: 48,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          ),
          const SizedBox(
            height: DesignConstants.spacingLarge,
          ),
          Text(
            message,
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
    );
  }
}
