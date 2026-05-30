import 'package:flutter/material.dart';

import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/table/cells/member_contact_cell.dart';
import 'package:app_management/features/members/presentation/widgets/table/cells/member_last_class_cell.dart';
import 'package:app_management/features/members/presentation/widgets/table/cells/member_name_cell.dart';
import 'package:app_management/shared/widgets/app_data_table.dart';

/// Members table — Name / Contact / Last Class columns.
///
/// Wraps [AppDataTable] so the sticky-header / sized-column /
/// row-tap behaviour stays consistent with every other table in
/// the app. Tapping a row navigates to the member detail screen.
class MembersTable extends StatelessWidget {
  final List<Member> members;

  const MembersTable({super.key, required this.members});

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      shrinkWrap: true,
      columns: const [
        AppDataTableColumn(label: 'Name', minWidth: 200, fill: true),
        AppDataTableColumn(label: 'Contact', minWidth: 220, fill: true),
        AppDataTableColumn(label: 'Last Class', minWidth: 140, fill: true),
      ],
      rows: members.map((m) {
        return AppDataTableRow(
          onTap: () {
            debugPrint(
              'Open member detail for ${m.fullName} (${m.id})',
            );
            Navigator.pushNamed(context, AppRoutes.memberDetail);
          },
          cells: [
            MemberNameCell(member: m),
            MemberContactCell(email: m.email),
            MemberLastClassCell(daysAgo: m.lastClassDaysAgo),
          ],
        );
      }).toList(),
    );
  }
}
