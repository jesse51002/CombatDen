import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/layouts/parts/rank_topbar.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_summary_section.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';

/// `RankFormat.sparkleStack` — the arrangement that ships today.
///
/// Streak hero at full size, then the rank summary (current rank, plot,
/// range pills), the next rank, and the level-up videos, each separated
/// by a rule. This layout reproduces the previous `ProfileScreen`
/// rendering value for value, so a tenant with no layout slot sees no
/// change.
class RankSparkleStack extends StatelessWidget {
  const RankSparkleStack({super.key, required this.data});

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
        RankStreakHero(weeks: profile.streakWeeks),
        RankSummarySection(profile: profile),
        const SectionDivider(),
        NextRankSection(
          title: profile.nextRankTitle,
          progressLabel: profile.nextRankProgressLabel,
          progress: profile.nextRankProgress,
          badgeAsset: profile.nextRankBadgeAsset,
        ),
        const SectionDivider(),
        const LevelUpVideosSection(),
      ],
    );
  }
}
