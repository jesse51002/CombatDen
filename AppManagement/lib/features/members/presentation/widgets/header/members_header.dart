import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';

/// Title + summary subtitle for the Members screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3578`.
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
          '${summary.frozen} frozen members',
          style: DesignConstants.h1Regular.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
