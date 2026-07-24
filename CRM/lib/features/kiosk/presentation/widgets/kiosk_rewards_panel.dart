import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/kiosk/presentation/kiosk_app_copy.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_app_line.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reveal.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_reward_tile.dart';
import 'package:crm/features/rewards/data/models/reward_response.dart';
import 'package:crm/shared/widgets/app_spinner.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The glance's right half — the member's points balance + the just-earned
/// delta over the image-first reward tiles, always closing on a calm app
/// nudge. The nudge never disappears: with rewards it points at
/// redemption, without them (or a failed catalog fetch) it points at booking,
/// so a no-rewards gym's glance isn't a lone "YOUR POINTS" eyebrow over empty
/// space. Degrades gracefully otherwise: a null [pointsBalance] (billing fetch
/// failed) drops the balance line and shows cost-only tiles; an empty [rewards]
/// gym shows a points-only panel (no grid). On a repeat check-in
/// ([alreadyCheckedIn]) the "+N pts" celebration chip is suppressed (it earned
/// none).
class KioskRewardsPanel extends StatelessWidget {
  final int? pointsBalance;
  final int pointsAwarded;
  final List<RewardResponse> rewards;
  final bool loading;
  final bool alreadyCheckedIn;

  const KioskRewardsPanel({
    super.key,
    required this.pointsBalance,
    required this.pointsAwarded,
    required this.rewards,
    required this.loading,
    this.alreadyCheckedIn = false,
  });

  @override
  Widget build(BuildContext context) {
    return KioskGlancePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          _RewardsHead(
            balance: pointsBalance,
            awarded: pointsAwarded,
            alreadyCheckedIn: alreadyCheckedIn,
          ),
          Expanded(child: _GridArea(rewards: rewards, balance: pointsBalance,
              loading: loading)),
          // The app funnel always closes the panel — only hidden while the
          // catalog is still loading (the grid shows a spinner and we don't yet
          // know which nudge fits).
          if (!loading) _AppFooter(hasRewards: rewards.isNotEmpty),
        ],
      ),
    );
  }
}

class _RewardsHead extends StatelessWidget {
  final int? balance;
  final int awarded;
  final bool alreadyCheckedIn;

  const _RewardsHead({
    required this.balance,
    required this.awarded,
    required this.alreadyCheckedIn,
  });

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
            // No "+N pts" celebration on a repeat check-in — it awards none.
            if (awarded > 0 && !alreadyCheckedIn) _EarnedChip(awarded: awarded),
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
        Text(formatKioskPoints(balance), style: DesignConstants.kioskMetric),
        Text(
          'points',
          style: DesignConstants.kioskBody.copyWith(
            fontWeight: FontWeight.w600,
            color: DesignConstants.text2nd,
          ),
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
        style: DesignConstants.kioskLabel.copyWith(
          fontWeight: FontWeight.w700,
          color: DesignConstants.onAccent,
        ),
      ),
    );
  }
}

/// The vertically-centred tile grid — a spinner while loading, the 2x2 grid
/// when rewards exist, or nothing (points-only) for a gym with no rewards.
///
/// The tiles arrive ONE BY ONE ([KioskRevealTimings.tileStagger]) rather than
/// as a block, so the payout reads as a payout.
///
/// **Each tile carries the panel's own beat offset, not just its stagger
/// slot.** A `KioskReveal` delay runs from the widget's MOUNT, and this grid
/// mounts whenever the catalog + balance land — which is long before the
/// panels beat. A bare `tileStagger * index` would therefore cascade the tiles
/// invisibly, behind a card that is still at zero opacity, and the member
/// would see four tiles simply present. Starting each tile at
/// [KioskRevealTimings.panels] puts the cascade back inside the beat that
/// actually shows it; a slow fetch only pushes the tiles that fetch's own
/// latency behind their card, never in front of it.
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
            for (final (index, reward) in rewards.indexed)
              KioskReveal(
                delay: KioskRevealTimings.panels +
                    KioskRevealTimings.tileStagger * index,
                child: KioskRewardTile(reward: reward, balance: balance),
              ),
          ],
        ),
      ),
    );
  }
}

/// The always-present app funnel under the grid: redemption when the gym has
/// rewards, booking otherwise — so the nudge never vanishes.
class _AppFooter extends StatelessWidget {
  final bool hasRewards;

  const _AppFooter({required this.hasRewards});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        const Hairline(),
        Center(
          child: KioskAppLine(
            // White-labelled: it is the GYM's app, not the platform's — see
            // `kiosk_app_copy.dart`. The gym is read straight off the global
            // `selectedGym`, the same way the kiosk header names it.
            text: hasRewards
                ? kioskRedeemInAppLine(selectedGym.gymName)
                : kioskBookInAppLine(selectedGym.gymName),
          ),
        ),
      ],
    );
  }
}
