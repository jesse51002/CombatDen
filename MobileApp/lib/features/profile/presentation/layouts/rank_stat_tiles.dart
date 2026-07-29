import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_tile.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_topbar.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_header.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/timeframe_selector.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// The hero scaled to a cell. Small enough that its sparkles read as
/// texture rather than as the screen's main event.

/// `RankFormat.statTiles` — a dashboard.
///
/// A 2x2 board opens the screen (streak, current rank, next rank, the
/// range selector) and the plot runs full bleed beneath it. The most
/// data-forward of the five.
class RankStatTiles extends StatelessWidget {
  const RankStatTiles({super.key, required this.data});

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
            horizontal: DesignConstants.screenHorizontalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingMedium,
            children: [
              // The streak hero sits ABOVE the board, unwrapped. It is
              // the app's celebration signature and renders at its own
              // intrinsic size; a tile imposes a fixed height, which is
              // what forced the earlier scale-down that read as squashed
              // rather than small. The board stays a board beneath it.
              RankStreakHero(weeks: profile.streakWeeks),
              _TileRow(
                left: RankHeader(
                  rankTitle: profile.rankTitle,
                  rankSubtitle: profile.rankSubtitle,
                  rankBadgeAsset: profile.rankBadgeLargeAsset,
                  layout: RankHeaderLayout.tile,
                ),
                right: const TimeframeSelector(
                  layout: TimeframeLayout.tile,
                ),
              ),
              RankTile(
                child: NextRankSection(
                  title: profile.nextRankTitle,
                  progressLabel: profile.nextRankProgressLabel,
                  progress: profile.nextRankProgress,
                  badgeAsset: profile.nextRankBadgeAsset,
                  layout: NextRankLayout.tile,
                ),
              ),
            ],
          ),
        ),
        const RatingGraph(size: RatingGraphSize.lg, bleed: true),
        const SectionDivider(),
        const LevelUpVideosSection(),
      ],
    );
  }
}

/// Two equal cells sharing a row of the board.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    // Not `stretch`: the board sits in a scroll view, where the row's
    // height is unbounded. Each tile fixes its own height instead, and
    // the pair reads as a pair because that height is the same.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(child: RankTile(child: left)),
        Expanded(child: RankTile(child: right)),
      ],
    );
  }
}
