import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reward_tile.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// Slide 2 — "Earn rewards": the gym's own warmed reward catalogue (active,
/// cheapest-first, capped at four) as the 2x2 grid.
///
/// Tiles are the glance's [KioskRewardTile] with `balance: null`, so each
/// shows its cost only (no ready disc / progress ring): this slide markets
/// what the gym offers, it is not a read-out of one member's standing.
class KioskRewardsSlide extends StatelessWidget {
  final List<RewardResponse> rewards;

  const KioskRewardsSlide({super.key, required this.rewards});

  @override
  Widget build(BuildContext context) {
    return KioskSlideBody(
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignConstants.kioskGlanceMeasure,
        ),
        child: FillGrid(
          columns: 2,
          stretchShortRows: false,
          spacing: DesignConstants.spacingLarge,
          children: [
            for (final reward in rewards)
              KioskRewardTile(reward: reward, balance: null),
          ],
        ),
      ),
    );
  }
}
