import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/refresh/app_refresh.dart';
import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_state.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_grid/rewards_grid.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_topbar.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/nav_tabs.dart';
import 'package:mobile_app/shared/widgets/refresh/app_refresh_view.dart';
import 'package:mobile_app/shared/widgets/refresh/selected_member_scope.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// My Rewards body: the member's redemption history over the per-member chrome.
class MyRewardsBody extends StatelessWidget {
  const MyRewardsBody({super.key});

  /// The shared pull: identity + capabilities + branding, theme, the shared
  /// profile, and this screen's redemptions — all awaited.
  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<RewardsBloc>();
    return AppRefresh.forScreen(
      context,
      screen: () => dispatchRefresh(bloc, RewardsRefreshRequested.new),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelectedMemberScope(
      builder: (context) => AppScreenScaffold(
        horizontalPadding: AppScreenHorizontalPadding.none,
        bottomNav: AppBottomNavBar(
          selected: AppBottomNavTab.reward,
          tabs: gymNavTabs(),
        ),
        child: AppRefreshView(
          onRefresh: () => _refresh(context),
          child: SingleChildScrollView(
            // "No rewards redeemed yet" is shorter than the viewport; without
            // this the emptiest page would be the one that refuses the pull.
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                const RewardsTopbar(),
                RewardsTabs(
                  active: RewardsTab.myRewards,
                  onPointsStoreTap: () => Navigator.of(context)
                      .pushReplacementNamed(AppRoutes.pointsStore),
                ),
                const _MyRewardsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The redemptions grid with its loading / retry-able error / empty states.
class _MyRewardsSection extends StatelessWidget {
  const _MyRewardsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RewardsBloc, RewardsState>(
      builder: (context, state) {
        switch (state.status) {
          case RewardsStatus.initial:
          case RewardsStatus.loading:
            return const RewardsLoadStatus(null);
          case RewardsStatus.error:
            return RewardsLoadStatus(
              state.errorMessage ?? 'Could not load your rewards.',
              onRetry: () => context
                  .read<RewardsBloc>()
                  .add(const RewardsLoadRequested()),
            );
          case RewardsStatus.loaded:
            if (state.redemptions.isEmpty) {
              return const RewardsLoadStatus('No rewards redeemed yet.');
            }
            return RewardsGrid(redemptions: state.redemptions);
        }
      },
    );
  }
}
