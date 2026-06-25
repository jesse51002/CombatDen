import 'package:flutter/material.dart';
import 'package:crm/showcase/showcase_slots.dart';
import 'package:theme_flutter/theme/theme_image.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members/data/mock_member_history.dart';

/// Rank icon + label, centered. Sits in the left column of the rank grid and
/// spans both rows. The icon follows the **selected style** — it resolves the
/// theme's `rank_belt` slot (the same image the member-app preview's topbar
/// uses), falling back to the member's bundled belt when no style is loaded.
class RankDisplay extends StatelessWidget {
  final DemoMember member;

  const RankDisplay({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Image(
          image: ThemeImage.image(
            ShowcaseSlots.rankBelt,
            fallback: AssetImage(member.rankIconAsset),
          ),
          width: 153,
          height: DesignConstants.rankBeltHeight,
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
