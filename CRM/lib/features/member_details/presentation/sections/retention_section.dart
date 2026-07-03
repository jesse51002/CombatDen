import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/retention_thresholds.dart';
import 'package:crm/features/member_details/data/models/pending_redemption.dart';
import 'package:crm/features/member_details/data/models/retention.dart';
import 'package:crm/features/member_details/data/models/reward_card_model.dart';
import 'package:crm/features/member_details/presentation/dialogs/adjust_points_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/redeem_reward_dialog.dart';
import 'package:crm/features/member_details/presentation/sections/pending_approvals_section.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/section_card.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Height of the horizontal reward strip — fixed so it measures
/// cleanly under the grid's equal-height layout. Sized to fit a
/// card's image, a one-line title, and a two-line description.
const double _kRewardStripHeight = 140;

/// Retention stats (last class, class streak, points,
/// videos watched) with threshold-driven coloring, plus a
/// horizontal strip of recently redeemed rewards.
///
/// Also provides "Redeem reward" and "Award / adjust points"
/// action buttons that open their respective dialogs and
/// dispatch bloc events on confirm, and — when any exist —
/// the member's pending redemption approvals as a subsection
/// (same card, between the actions and the redeemed strip).
class RetentionSection extends StatelessWidget {
  final Retention retention;
  final List<RewardCardModel> rewards;
  final List<PendingRedemption> pendingRedemptions;
  final String memberId;
  final String memberName;
  final String gymId;

  const RetentionSection({
    super.key,
    required this.retention,
    required this.rewards,
    required this.pendingRedemptions,
    required this.memberId,
    required this.memberName,
    required this.gymId,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Text('Retention', style: DesignConstants.h2),
          _RetentionGrid(retention: retention),
          _RewardsActions(
            memberId: memberId,
            memberName: memberName,
            gymId: gymId,
            pointsBalance: retention.pointsBalance,
            pendingRewardIds: {
              for (final r in pendingRedemptions) r.rewardId,
            },
          ),
          if (pendingRedemptions.isNotEmpty)
            PendingApprovalsSection(
              pendingRedemptions: pendingRedemptions,
              memberName: memberName,
            ),
          SubtitleSection(
            title: 'Recently redeemed rewards',
            child: rewards.isEmpty
                ? _EmptyRewards()
                : SizedBox(
                    height: _kRewardStripHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: rewards.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(
                        width: DesignConstants.spacingMedium,
                      ),
                      itemBuilder: (_, i) => _RewardCard(
                        reward: rewards[i],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Inline action bar for rewards staff actions.
class _RewardsActions extends StatelessWidget {
  final String memberId;
  final String memberName;
  final String gymId;
  final int pointsBalance;
  final Set<String> pendingRewardIds;

  const _RewardsActions({
    required this.memberId,
    required this.memberName,
    required this.gymId,
    required this.pointsBalance,
    required this.pendingRewardIds,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        AppOutlineButton(
          text: 'Redeem reward',
          icon: Icon(
            Symbols.redeem_sharp,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
          ),
          onPressed: () => RedeemRewardDialog.show(
            context: context,
            gymId: gymId,
            memberId: memberId,
            memberName: memberName,
            pointsBalance: pointsBalance,
            pendingRewardIds: pendingRewardIds,
          ),
        ),
        AppOutlineButton(
          text: 'Award / adjust pts',
          icon: Icon(
            Symbols.star_sharp,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
          ),
          onPressed: () => AdjustPointsDialog.show(
            context: context,
            memberId: memberId,
            memberName: memberName,
            currentBalance: pointsBalance,
          ),
        ),
      ],
    );
  }
}

class _RetentionGrid extends StatelessWidget {
  final Retention retention;

  const _RetentionGrid({required this.retention});

  @override
  Widget build(BuildContext context) {
    final daysSince = retention.daysSinceLastClass;
    return Column(
      spacing: DesignConstants.spacingLarge,
      children: [
        Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(
              child: _RetentionStat(
                icon: Symbols.schedule_sharp,
                value: daysSince != null
                    ? '$daysSince days ago'
                    : 'No classes',
                label: 'Last class',
                valueColor: daysSince != null
                    ? RetentionThreshold.getLastClassColor(
                        daysSince,
                      )
                    : DesignConstants.text2nd,
              ),
            ),
            Expanded(
              child: _RetentionStat(
                icon: Symbols.bolt_sharp,
                value:
                    '${retention.classStreakWeeks} weeks',
                label: 'Class streak',
                valueColor:
                    RetentionThreshold.getStreakColor(
                  retention.classStreakWeeks,
                ),
              ),
            ),
          ],
        ),
        Row(
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(
              child: _RetentionStat(
                icon: Symbols.star_sharp,
                value: '${retention.pointsBalance} points',
                label: 'Points balance',
                valueColor: DesignConstants.text,
              ),
            ),
            Expanded(
              child: _RetentionStat(
                icon: Symbols.play_arrow_sharp,
                value: '${retention.videosWatched} videos',
                label: 'Videos watched',
                valueColor: DesignConstants.text,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RetentionStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color valueColor;

  const _RetentionStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          icon,
          color: valueColor,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingTiny,
            children: [
              Text(
                value,
                style: DesignConstants.h2.copyWith(
                  color: valueColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: DesignConstants.h3.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyRewards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.paddingBig,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Center(
        child: Text(
          'No rewards claimed yet',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final RewardCardModel reward;

  const _RewardCard({required this.reward});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingSmall,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
            child: SizedBox(
              width: 120,
              height: DesignConstants.rewardThumbnailHeight,
              child: reward.imageUrl != null
                  ? Image.network(
                      reward.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const _RewardPlaceholder(),
                    )
                  : const _RewardPlaceholder(),
            ),
          ),
          Text(
            reward.title,
            style: DesignConstants.h3,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (reward.priceLabel != null)
            Text(
              reward.priceLabel!,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _RewardPlaceholder extends StatelessWidget {
  const _RewardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignConstants.backgroundColor,
      child: Center(
        child: Icon(
          Symbols.redeem_sharp,
          color: DesignConstants.text3rd,
          size: DesignConstants.iconSizeBig,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}
