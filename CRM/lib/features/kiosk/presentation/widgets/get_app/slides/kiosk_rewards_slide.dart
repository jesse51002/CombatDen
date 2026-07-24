import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/get_app/kiosk_showcase_slide.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reward_tile.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// Slide 2 — "Earn rewards": the gym's own reward catalogue as the 2x2
/// grid.
///
/// **Data source: REAL.** The cubit warms the gym-wide reward catalogue once
/// at kiosk entry and publishes it to the state, so these are this gym's
/// actual rewards (active, cheapest-first, capped at four) with their real
/// images, price labels and point costs — on the home path as well as the
/// glance path.
///
/// Tiles are the glance's [KioskRewardTile] with `balance: null`, so each
/// shows its cost only (no ready disc / progress ring): this slide markets
/// what the gym offers, it is not a read-out of one member's standing.
///
/// The slide is only built when the catalogue is non-empty — a gym with no
/// rewards (or a failed fetch) omits it entirely rather than showing
/// placeholder demo rewards, so [rewards] here is always populated.
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
