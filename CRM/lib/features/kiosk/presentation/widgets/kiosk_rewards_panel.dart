import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reward_tile.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The glance's right half — the member's points balance + the just-earned
/// delta over the image-first reward tiles, with a calm "redeem in the app"
/// footer (mockup `.rewards`). Degrades gracefully: a null [pointsBalance]
/// (billing fetch failed) drops the balance line and shows cost-only tiles;
/// an empty [rewards] gym shows a points-only panel (no grid, no footer).
class KioskRewardsPanel extends StatelessWidget {
  final int? pointsBalance;
  final int pointsAwarded;
  final List<RewardResponse> rewards;
  final bool loading;

  const KioskRewardsPanel({
    super.key,
    required this.pointsBalance,
    required this.pointsAwarded,
    required this.rewards,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final hasRewards = !loading && rewards.isNotEmpty;
    return KioskGlancePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          _RewardsHead(balance: pointsBalance, awarded: pointsAwarded),
          Expanded(child: _GridArea(rewards: rewards, balance: pointsBalance,
              loading: loading)),
          if (hasRewards) const _RedeemFooter(),
        ],
      ),
    );
  }
}

class _RewardsHead extends StatelessWidget {
  final int? balance;
  final int awarded;

  const _RewardsHead({required this.balance, required this.awarded});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text('YOUR POINTS', style: DesignConstants.kioskEyebrow),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            if (balance != null) _Balance(balance: balance!),
            if (awarded > 0) _EarnedChip(awarded: awarded),
          ],
        ),
      ],
    );
  }
}

class _Balance extends StatelessWidget {
  final int balance;

  const _Balance({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: DesignConstants.spacingSmall,
      children: [
        Text(formatKioskPoints(balance), style: DesignConstants.big2Bold),
        Text(
          'points',
          style: DesignConstants.h2.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}

/// The "+N pts" celebration pill — the points earned by THIS check-in.
class _EarnedChip extends StatelessWidget {
  final int awarded;

  const _EarnedChip({required this.awarded});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: ShapeDecoration(
        color: DesignConstants.primaryColor,
        shape: const StadiumBorder(),
      ),
      child: Text(
        '+${formatKioskPoints(awarded)} pts',
        style: DesignConstants.h2Bold.copyWith(color: DesignConstants.onAccent),
      ),
    );
  }
}

/// The vertically-centred tile grid — a spinner while loading, the 2x2 grid
/// when rewards exist, or nothing (points-only) for a gym with no rewards.
class _GridArea extends StatelessWidget {
  final List<RewardResponse> rewards;
  final int? balance;
  final bool loading;

  const _GridArea({
    required this.rewards,
    required this.balance,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: AppSpinner());
    if (rewards.isEmpty) return const SizedBox.shrink();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignConstants.kioskGlanceMeasure,
        ),
        child: FillGrid(
          columns: 2,
          stretchShortRows: false,
          spacing: DesignConstants.spacingLarge,
          children: [
            for (final reward in rewards)
              KioskRewardTile(reward: reward, balance: balance),
          ],
        ),
      ),
    );
  }
}

class _RedeemFooter extends StatelessWidget {
  const _RedeemFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        const Center(
          child: KioskAppLine(text: 'Redeem rewards in the CombatDen app'),
        ),
      ],
    );
  }
}
