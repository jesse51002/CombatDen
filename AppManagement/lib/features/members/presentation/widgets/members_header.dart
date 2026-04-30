import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';

/// Page title block for the Members screen — the bold "Members" heading
/// and a single-line summary of active / trial / frozen counts.
class MembersHeader extends StatelessWidget {
  final MembersSummary summary;

  const MembersHeader({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Members', style: DesignConstants.big2),
        Text(
          '${summary.active} active members, '
          '${summary.trial} trial members, '
          '${summary.frozen} frozen members',
          style: DesignConstants.h1Regular.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
