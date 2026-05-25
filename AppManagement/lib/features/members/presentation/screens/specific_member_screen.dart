import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/member_profile_card.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/member_quick_list/member_quick_list.dart';
import 'package:app_management/shared/widgets/app_shell.dart';
import 'package:app_management/shared/widgets/hairline.dart';

/// Member detail screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3075`.
/// Composition (left to right):
///   1. SectionsBar (provided by AppShell, active item = Members)
///   2. Main column with the member profile card
///   3. Right rail with a search box and member quick-list
class SpecificMemberScreen extends StatelessWidget {
  const SpecificMemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.members,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(
                DesignConstants.paddingBig,
              ),
              child: MemberProfileCard(
                member: kMockDemoMember,
                stats: kMockMemberDetailStats,
              ),
            ),
          ),
          const Hairline(vertical: true),
          MemberQuickList(members: kMockMembers),
        ],
      ),
    );
  }
}
