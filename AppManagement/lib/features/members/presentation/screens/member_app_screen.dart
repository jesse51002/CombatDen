import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_member_app_preview.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/gym_logo/gym_logo_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/gym_type/gym_type_card.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/rewards/rewards_store_card.dart';
import 'package:app_management/shared/widgets/app_shell.dart';

/// Admin-side preview / configurator for what the member sees in the
/// CombatDen mobile app.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3427`.
/// Composition (top to bottom):
///   1. Gym logo + name card with "Edit Name / Logo".
///   2. Gym Type card — admin picks MMA / Judo / Boxing / Karate.
///   3. In-app Rewards Store card — points tiers + Add-more grid.
class MemberAppScreen extends StatelessWidget {
  const MemberAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const data = kMockMemberAppPreview;

    return AppShell(
      activeRoute: AppRoutes.memberAppPreview,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            GymLogoCard(
              gymName: data.gymName,
              logoAsset: data.gymLogoAsset,
            ),
            GymTypeCard(selected: data.selectedGymType),
            RewardsStoreCard(
              rewards: data.rewards,
              addableRewards: data.addableRewards,
            ),
          ],
        ),
      ),
    );
  }
}
