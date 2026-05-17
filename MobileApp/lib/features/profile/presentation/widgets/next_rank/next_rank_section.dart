import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_badge.dart';

/// "Next Rank: Blue Stripe III (45% left)" label with a circular
/// progress-ring belt badge on the right.
class NextRankSection extends StatelessWidget {
  const NextRankSection({
    super.key,
    required this.title,
    required this.progressLabel,
    required this.progress,
    required this.badgeAsset,
  });

  final String title;
  final String progressLabel;
  final double progress;
  final String badgeAsset;

  @override
  Widget build(BuildContext context) {
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
                Text(title, style: DesignConstants.h2),
                Text(
                  progressLabel,
                  style: DesignConstants.h2Regular.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
          NextRankBadge(badgeAsset: badgeAsset, progress: progress),
        ],
      ),
    );
  }
}
