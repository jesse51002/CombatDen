import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/shared/widgets/app_search_box.dart';
import 'package:app_management/shared/widgets/member_list_item.dart';

/// Right-side rail on the SpecificMember screen. Lets the user jump
/// between members without going back to the full Members list.
///
/// Holds a search box and a vertically scrollable list of member
/// rows (name).
class MemberQuickList extends StatelessWidget {
  final List<Member> members;

  const MemberQuickList({super.key, required this.members});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(DesignConstants.paddingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          const AppSearchBox(hintText: 'search...'),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingLarge,
                children: [
                  for (final member in members)
                    _Row(member: member),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Member member;
  const _Row({required this.member});

  @override
  Widget build(BuildContext context) {
    return MemberListItem(
      name: member.fullName,
      onTap: () => Navigator.pushReplacementNamed(
        context,
        AppRoutes.memberDetail,
      ),
    );
  }
}
