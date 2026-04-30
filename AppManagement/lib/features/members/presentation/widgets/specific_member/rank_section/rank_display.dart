import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';

/// Belt icon + rank label, centered. Sits in the left column of the
/// rank grid and spans both rows.
class RankDisplay extends StatelessWidget {
  final DemoMember member;

  const RankDisplay({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Image.asset(
          member.rankIconAsset,
          width: 153,
          height: 99,
          fit: BoxFit.contain,
        ),
        Text(
          member.rankLabel,
          style: DesignConstants.h2,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
