import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_graph_strip.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_topbar.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// The streak reads as a line in the "now" half, not as the hero.
const double _kLineHeroHeight = 76;

/// `RankFormat.splitRank` — now over next.
///
/// The screen splits into where the member IS and what comes NEXT, with
/// the plot as a collapsible strip on the seam between them. The
/// clearest information architecture of the five and the least visually
/// eventful.
class RankSplitRank extends StatelessWidget {
  const RankSplitRank({super.key, required this.data});

  final RankLayoutData data;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        RankTopbar(data: data),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: RankHeader(
                rankTitle: profile.rankTitle,
                rankSubtitle: profile.rankSubtitle,
                rankBadgeAsset: profile.rankBadgeLargeAsset,
                layout: RankHeaderLayout.beltLeft,
              ),
            ),
            RankStreakHero(
              weeks: profile.streakWeeks,
              maxHeight: _kLineHeroHeight,
            ),
          ],
        ),
        const RankGraphStrip(),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
          ),
          child: NextRankSection(
            title: profile.nextRankTitle,
            progressLabel: profile.nextRankProgressLabel,
            progress: profile.nextRankProgress,
            badgeAsset: profile.nextRankBadgeAsset,
            layout: NextRankLayout.stacked,
          ),
        ),
        const SectionDivider(),
        const LevelUpVideosSection(),
      ],
    );
  }
}
