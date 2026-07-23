import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_bloc.dart';
import 'package:mobile_app/features/profile/bloc/rank_progress_event.dart';
import 'package:mobile_app/features/profile/data/repositories/member_rank_progress_repository.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/next_rank_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/profile_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/widgets/profile_topbar.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rank_summary_section.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

// Bottom scroll padding to clear the persistent bottom nav.
const double _kBottomScrollPadding = 64;

/// Profile / rank screen. The topbar + streak hero + rank block read the
/// app-wide [MemberProfileBloc] (provided above the shell); the rank-progress
/// graph gets its own [RankProgressBloc] scoped to this screen.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<RankProgressBloc>(
      create: (_) => RankProgressBloc(
        repository: MemberRankProgressRepository(apiClient: ApiClient()),
      )..add(const RankProgressLoadRequested()),
      child: const _ProfileScaffold(),
    );
  }
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold();

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.rank),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: _kBottomScrollPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: const [
            ProfileTopbar(),
            ProfileStreakHero(),
            _ProfileBody(),
          ],
        ),
      ),
    );
  }
}

/// The rank block (only when the member holds a rank) over the level-up videos.
/// A rank of `null` — ranks disabled or none assigned — hides the rank summary,
/// the next-rank card, and their dividers, leaving the level-up carousel.
class _ProfileBody extends StatelessWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) {
        final rank = state.profile?.rank;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingBig,
          children: [
            if (rank != null) ...[
              RankSummarySection(rank: rank),
              const SectionDivider(),
              NextRankSection(rank: rank),
              const SectionDivider(),
            ],
            const LevelUpVideosSection(),
          ],
        );
      },
    );
  }
}
