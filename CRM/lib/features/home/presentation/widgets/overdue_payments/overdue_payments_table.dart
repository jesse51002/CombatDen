import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/screens/member_detail_screen.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/member_name_cell.dart';
import 'package:crm/features/members/presentation/widgets/table/cells/simple_text_cell.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// Minimal overdue-members table for the dashboard: member
/// (avatar + name) and how many days late they are.
///
/// Shrink-wraps so it grows the dashboard's scroll view (the
/// non-shrink path sizes to bounded height and crashes under
/// a `SingleChildScrollView`). Tapping a row opens that
/// member's detail screen.
class OverduePaymentsTable extends StatelessWidget {
  final List<OverdueViewRow> rows;

  const OverduePaymentsTable({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      shrinkWrap: true,
      columns: const [
        AppDataTableColumn(
          label: 'Member',
          minWidth: 180,
          fill: true,
        ),
        AppDataTableColumn(
          label: 'Days Late',
          minWidth: 120,
        ),
      ],
      rows: rows.map((row) {
        return AppDataTableRow(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MemberDetailScreen(
                  memberId: row.memberId,
                ),
              ),
            );
          },
          cells: [
            MemberNameCell(
              name: row.name,
              avatarUrl: row.avatarUrl,
            ),
            SimpleTextCell(
              text: '${row.daysLate} days',
              color: DesignConstants.badRed,
            ),
          ],
        );
      }).toList(),
    );
  }
}
