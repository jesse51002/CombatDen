import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/controls/members_controls.dart';
import 'package:app_management/features/members/presentation/widgets/header/members_header.dart';
import 'package:app_management/features/members/presentation/widgets/table/members_table.dart';
import 'package:app_management/shared/widgets/app_shell.dart';

/// Gym admin Members list screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3574`.
/// Composition (top to bottom):
///   1. "Members" title + summary subtitle (active / trial / frozen).
///   2. Search box + "Add New Member" primary button.
///   3. "Add Filter +" pill.
///   4. Tappable table of members — Name / Contact / Rank / Last Class.
class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.members,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.paddingBig,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: const MembersHeader(
                summary: kMockMembersSummary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: const MembersControls(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingSmall,
              ),
              child: const MembersTable(members: kMockMembers),
            ),
          ],
        ),
      ),
    );
  }
}
