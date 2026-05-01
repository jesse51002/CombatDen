import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_tile_row.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/sparkle_burst.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/brand_image.dart';

/// Trophy hero with one-shot sparkle burst, "Today's wins" header, and the
/// three info tiles cascading in left-to-right.
class WinsBody extends StatelessWidget {
  const WinsBody({super.key, required this.stats});

  final MockWinsStats stats;

  @override
  Widget build(BuildContext context) {
    final headerDelay = CelebrationTimings.revealStagger;
    final subtitleDelay = headerDelay + CelebrationTimings.revealStagger;
    final tileBaseDelay = subtitleDelay + CelebrationTimings.revealDuration;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        SizedBox(
          width: 320,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: SparkleBurst(size: 320)),
              StaggeredReveal(
                offset: 0,
                child: BrandImage.asset(
                  stats.heroAsset,
                  width: 230,
                  height: 230,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            StaggeredReveal(
              delay: headerDelay,
              child: Text(
                stats.title,
                textAlign: TextAlign.center,
                style: DesignConstants.big2,
              ),
            ),
            StaggeredReveal(
              delay: subtitleDelay,
              child: Text(
                stats.subtitle,
                textAlign: TextAlign.center,
                style: DesignConstants.pBig.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ],
        ),
        WinsTileRow(tiles: stats.tiles, baseDelay: tileBaseDelay),
      ],
    );
  }
}
