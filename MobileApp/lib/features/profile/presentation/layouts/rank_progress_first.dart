import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_topbar.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// The streak demotes to a line so the arc keeps the top of the screen.

/// `RankFormat.progressFirst` — the arc leads.
///
/// Next-rank progress is promoted to a large arc with the belt inside
/// it, answering the one question a graded-art member opens this screen
/// to ask. The streak drops to a line and the current rank to a row
/// beneath it.
class RankProgressFirst extends StatelessWidget {
  const RankProgressFirst({super.key, required this.data});

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
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
          ),
          child: NextRankSection(
            title: profile.nextRankTitle,
            progressLabel: profile.nextRankProgressLabel,
            progress: profile.nextRankProgress,
            badgeAsset: profile.nextRankBadgeAsset,
            layout: NextRankLayout.arc,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            RankStreakHero(weeks: profile.streakWeeks),
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
          ],
        ),
        const SectionDivider(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: const TimeframeSelector(
                layout: TimeframeLayout.segmented,
              ),
            ),
            const RatingGraph(),
          ],
        ),
        const SectionDivider(),
        const LevelUpVideosSection(),
      ],
    );
  }
}
