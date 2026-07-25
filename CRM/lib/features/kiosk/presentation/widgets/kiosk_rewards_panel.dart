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
/// delta over the image-first reward tiles, always closing on an app nudge.
/// That nudge never disappears: redemption with rewards, booking without them,
/// so a no-rewards gym isn't left with a lone "YOUR POINTS" eyebrow over empty
/// space. A null [pointsBalance] (billing fetch failed) drops the balance line
/// and shows cost-only tiles; a repeat check-in suppresses the "+N pts" chip,
/// since it earned none.
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
          // Hidden only while the catalog loads — until it lands we don't
          // know which nudge fits.
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
/// when rewards exist, or nothing for a gym with no rewards. The tiles arrive
/// one by one so the payout reads as a payout.
///
/// Each tile's delay starts at [KioskRevealTimings.panels], not at a bare
/// `tileStagger * index`: a `KioskReveal` delay runs from MOUNT, and this grid
/// mounts when the catalog lands — long before the panels beat — so a stagger
/// from mount would cascade invisibly behind a card at zero opacity.
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

/// The always-present app funnel under the grid.
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
            // White-labelled: the GYM's app — see `kiosk_app_copy.dart`.
            text: hasRewards
                ? kioskRedeemInAppLine(selectedGym.gymName)
                : kioskBookInAppLine(selectedGym.gymName),
          ),
        ),
      ],
    );
  }
}
