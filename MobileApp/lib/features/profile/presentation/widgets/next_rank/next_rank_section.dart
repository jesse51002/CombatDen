import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_badge.dart';

// Bundled fallback next-rank belt, shown (under the themed slot) when the
// payload carries no next-rank image — the top of the ladder, or a rank whose
// belt art isn't set.
const String _kNextRankBeltAsset = 'profile_next_rank_belt.png';

/// "Next Rank — X / Y classes" with a circular progress-ring belt badge. The
/// progress is real attendance toward the next leaf: classes since the last
/// promotion vs the per-step threshold, the same derivation the CRM
/// member-detail rank card uses. At the top of the ladder there's no target.
class NextRankSection extends StatelessWidget {
  const NextRankSection({super.key, required this.rank});

  final BillingRank rank;

  @override
  Widget build(BuildContext context) {
    final target = rank.classesTillNextStep;
    final done = rank.classesSinceRank;
    final atTop = target <= 0;
    final progress = atTop ? 0.0 : (done / target).clamp(0.0, 1.0);
    final progressLabel =
        atTop ? 'Top of the ladder.' : '$done / $target classes';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingBig),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingSmall,
              children: [
                Text('Next Rank', style: DesignConstants.h2),
                Text(
                  progressLabel,
                  style: DesignConstants.h2Regular.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          NextRankBadge(
            badgeAsset: _kNextRankBeltAsset,
            progress: progress,
            imageUrl: rank.nextRankImageUrl,
          ),
        ],
      ),
    );
  }
}
