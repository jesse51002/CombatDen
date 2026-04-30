import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/cells/contact_cell.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/cells/last_class_cell.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/cells/name_cell.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/cells/rank_cell.dart';

/// One member's row across all four columns. Tapping the row routes
/// into the member detail screen; tapping the copy icon inside the
/// contact cell only copies the email and does not navigate.
class MembersTableRow extends StatelessWidget {
  final Member member;
  final VoidCallback onTap;
  final VoidCallback onCopyEmail;

  const MembersTableRow({
    super.key,
    required this.member,
    required this.onTap,
    required this.onCopyEmail,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.spacingSmall),
      child: SizedBox(
        height: DesignConstants.tableRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: NameCell(member: member)),
            Expanded(child: ContactCell(
              email: member.email,
              onCopy: onCopyEmail,
            )),
            Expanded(child: RankCell(rank: member.rank)),
            Expanded(child: LastClassCell(daysAgo: member.lastClassDaysAgo)),
          ],
        ),
      ),
    );
  }
}
