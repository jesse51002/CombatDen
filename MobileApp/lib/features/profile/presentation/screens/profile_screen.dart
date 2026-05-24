import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_summary_section.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

// Bottom scroll padding to clear the persistent bottom nav.
const double _kBottomScrollPadding = 64;

/// Profile screen.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = mockProfile;
    final gym = mockGym;
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.rank),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: _kBottomScrollPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            AppTopbar(
              mode: AppTopbarMode.nameOnly,
              showBackButton: false,
              gymName: profile.gymName,
              logoAsset: gym.logoAsset,
              streakDays: profile.streakDays,
              pointsLabel: profile.pointsLabel,
              rankBadgeAsset: profile.rankBadgeAsset,
            ),
            SparkleHero(
              top: 'YOU HAVE A',
              accent: '${profile.streakWeeks} WEEK',
              bottom: 'STREAK',
            ),
            _ProfileBody(profile: profile),
          ],
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile});

  final MockProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
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
