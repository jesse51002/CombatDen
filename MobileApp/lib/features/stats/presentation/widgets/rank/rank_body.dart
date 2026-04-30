import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/rank/rank_progress_bar.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';

/// Two-line rank name + belt illustration + tier-progress bar with caption.
class RankBody extends StatelessWidget {
  const RankBody({super.key, required this.stats});

  final MockRankStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              stats.rankTitle,
              textAlign: TextAlign.center,
              style: DesignConstants.big2,
            ),
            Text(
              stats.rankSubtitle,
              textAlign: TextAlign.center,
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        Center(
          child: BrandImage.asset(
            stats.beltAsset,
            width: 209,
            height: 208,
            fit: BoxFit.contain,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            RankProgressBar(
              previousFraction: stats.previousProgressFraction,
              currentFraction: stats.progressFraction,
            ),
            Text(
              '${stats.classesAttended}/${stats.classesRequired} classes '
              'to ${stats.nextTierLabel}',
              textAlign: TextAlign.center,
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
