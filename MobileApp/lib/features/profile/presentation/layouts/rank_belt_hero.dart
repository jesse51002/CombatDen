import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_topbar.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_badge.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_progress.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_progress_label.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_title.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// The streak sits over the belt band rather than under it, and the
/// small belt beside "Next Rank" reads at a glance next to the big one.
const double _kInlineBadgeSize = 56;

/// `RankFormat.beltHero` — the belt leads.
///
/// The current belt becomes a full-width band with the streak statement
/// over it, and the next-rank rail runs directly beneath, so "where I
/// am" and "what is next" are one glance instead of two scroll
/// positions. The plot demotes to a card lower down.
class RankBeltHero extends StatelessWidget {
  const RankBeltHero({super.key, required this.data});

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
          spacing: DesignConstants.spacingMedium,
          children: [
            Stack(
              alignment: Alignment.topCenter,
              children: [
                RankHeader(
                  rankTitle: profile.rankTitle,
                  rankSubtitle: profile.rankSubtitle,
                  rankBadgeAsset: profile.rankBadgeLargeAsset,
                  layout: RankHeaderLayout.beltBleed,
                ),
                RankStreakHero(weeks: profile.streakWeeks),
              ],
            ),
            NextRankProgress(
              progress: profile.nextRankProgress,
              layout: NextRankProgressLayout.rail,
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignConstants.paddingBig,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: DesignConstants.spacingLarge,
                children: [
                  NextRankBadge(
                    badgeAsset: profile.nextRankBadgeAsset,
                    size: _kInlineBadgeSize,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: DesignConstants.spacingSmall,
                      children: [
                        NextRankTitle(title: profile.nextRankTitle),
                        NextRankProgressLabel(
                          label: profile.nextRankProgressLabel,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SectionDivider(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: const [
            TimeframeSelector(),
            RatingGraph(card: true),
          ],
        ),
        const SectionDivider(),
        const LevelUpVideosSection(),
      ],
    );
  }
}
