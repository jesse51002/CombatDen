import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/finish_signup_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_contact_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_last_class_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_name_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_phone_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_status_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_waiting_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/simple_text_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/members_table_columns.dart';
import 'package:crm/features/members/presentation/widgets/table/members_table_empty_state.dart';
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
      return MembersTableEmptyState(
        activeView: activeView,
        hasActiveFilters: hasActiveFilters,
      );
    }

    return AppDataTable(
      infiniteScroll: !hasReachedEnd,
      isLoadingMore: isLoadingMore,
      onLoadMore: onLoadMore,
      columns: membersTableColumns(activeView),
      rows: members.map((row) {
        return AppDataTableRow(
          onTap: () => _openMember(context, row.memberId),
          cells: _cellsForRow(row, context),
        );
      }).toList(),
    );
  }

  /// Deep-links to a member's detail page. Shared by the whole-row tap
  /// and the Incomplete view's "Finish signup" action so both land on
  /// the same addressable URL.
  void _openMember(BuildContext context, String memberId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Name the route with the member id so the URL becomes
        // `/members/detail/<id>` and a reload restores this member.
        settings: RouteSettings(
          name: AppRoutes.memberDetailPath(memberId),
        ),
        builder: (_) => MemberDetailScreen(
          memberId: memberId,
          gymId: gymId,
        ),
      ),
    );
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
      IncompleteViewRow r => [
          MemberNameCell(name: r.name, avatarUrl: r.avatarUrl),
          MemberContactCell(email: r.email),
          MemberPhoneCell(phone: r.phone),
          MemberWaitingCell(daysWaiting: r.daysWaiting),
          FinishSignupCell(
            onPressed: () => _openMember(context, r.memberId),
          ),
        ],
    };
  }
}
