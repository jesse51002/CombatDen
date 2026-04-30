import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/members_row_divider.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/members_table_header.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/members_table_row.dart';

/// 4-column members list: Name, Contact, Rank, Last Class.
///
/// Layout matches the Figma frame `Members` (3132:3574) — each column
/// header underlined, each member row separated by a thin divider, the
/// whole row tappable to open the member detail screen.
class MembersTable extends StatelessWidget {
  final List<Member> members;
  final ValueChanged<Member> onRowTap;
  final ValueChanged<String> onCopyEmail;

  const MembersTable({
    super.key,
    required this.members,
    required this.onRowTap,
    required this.onCopyEmail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        const MembersTableHeader(),
        for (final member in members) ...[
          MembersTableRow(
            member: member,
            onTap: () => onRowTap(member),
            onCopyEmail: () => onCopyEmail(member.email),
          ),
          const MembersRowDivider(),
        ],
      ],
    );
  }
}
