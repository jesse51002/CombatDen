import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/refresh/app_refresh.dart';
import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/core/state/selected_member.dart';
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
import 'package:mobile_app/features/profile/presentation/widgets/rankless/rankless_profile_body.dart';
import 'package:mobile_app/shared/widgets/dividers/section_divider.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/nav_tabs.dart';
import 'package:mobile_app/shared/widgets/refresh/app_refresh_view.dart';
import 'package:mobile_app/shared/widgets/refresh/selected_member_scope.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

// Bottom scroll padding to clear the persistent bottom nav.
const double _kBottomScrollPadding = 64;

/// The member's retention surface — the "Profile" tab. Two shapes, chosen by
/// whether the gym runs a rank ladder at all (`selectedMember.gymRankEnabled`):
///
/// * **Rank enabled** — topbar + streak hero + the rank block over the level-up
///   videos, exactly as before.
/// * **Rank off** — the streak hero becomes the whole page: hero + this week's
///   day strip + two plain facts, vertically centred in the room the rank block
///   vacated. See [RanklessProfileBody].
///
/// The gate is the gym FLAG, not `rank == null`: a rank-enabled gym can
/// legitimately hold a member who hasn't been graded yet, and that member still
/// belongs on the rank-shaped page.
///
/// NO account actions live here — sign-out lives behind the topbar's identity
/// avatar.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Wrapped so a pull that flips `gymRankEnabled` re-chooses the shape then
    // and there — the founder-visible half of the bug this refresh exists for.
    // Flipping ranks ON also mounts the bloc below and fires its first load.
    return SelectedMemberScope(
      builder: (context) {
        // Ranks off ⇒ no rank graph, so don't build the bloc or fire its
        // fetch: the backend answers `points: []` for a rank-off gym, and that
        // is a round trip feeding a spinner nobody sees.
        if (!selectedMember.gymRankEnabled) return const _RanklessProfile();
        return BlocProvider<RankProgressBloc>(
          create: (_) => RankProgressBloc(
            repository: MemberRankProgressRepository(apiClient: ApiClient()),
          )..add(const RankProgressLoadRequested()),
          child: const _ProfileScaffold(),
        );
      },
    );
  }
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold();

  /// The shared pull. The profile leg already re-reads rank, points, streak
  /// and the week strip, so this screen's own leg is only the rank-progress
  /// GRAPH — the one thing on this page the shared profile doesn't carry.
  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<RankProgressBloc>();
    return AppRefresh.forScreen(
      context,
      screen: () => dispatchRefresh(bloc, RankProgressRefreshRequested.new),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: AppBottomNavBar(
        selected: AppBottomNavTab.rank,
        tabs: gymNavTabs(),
      ),
      child: AppRefreshView(
        onRefresh: () => _refresh(context),
        child: SingleChildScrollView(
          // An ungraded member at a rank-enabled gym gets a short page (no
          // rank block) — it must still take the pull.
          physics: const AlwaysScrollableScrollPhysics(),
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
      ),
    );
  }
}

/// The rank block (only when the member holds a rank) over the level-up
/// videos. A rank of `null` at a rank-ENABLED gym — a member not graded yet —
/// hides the rank summary, the next-rank card, and their dividers, leaving the
/// level-up carousel.
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

/// The rank-less shape: the same topbar (its belt tile collapsed), then the
/// streak block given the whole viewport.
class _RanklessProfile extends StatelessWidget {
  const _RanklessProfile();

  /// The shared pull. This shape owns NO data beyond the shared profile — the
  /// hero, week strip and facts all read it — so there is no screen leg, and
  /// nothing is dispatched twice.
  Future<void> _refresh(BuildContext context) => AppRefresh.forScreen(context);

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: AppBottomNavBar(
        selected: AppBottomNavTab.rank,
        tabs: gymNavTabs(),
      ),
      child: AppRefreshView(
        onRefresh: () => _refresh(context),
        child: CustomScrollView(
          // This page is deliberately viewport-sized (`SliverFillRemaining`
          // with no scroll body), so it has NO overscroll of its own — without
          // this the pull would be dead on the one tab most likely to be
          // rank-off.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: const [
            SliverToBoxAdapter(child: ProfileTopbar()),
            // Fills whatever the topbar left of the viewport, and grows past it
            // once the level-up carousel renders — so the streak block is
            // CENTRED in the space the rank block vacated instead of stranded at
            // the top of a short scroll.
            SliverFillRemaining(
              hasScrollBody: false,
              child: RanklessProfileBody(
                bottomPadding: _kBottomScrollPadding,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
