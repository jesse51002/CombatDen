import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_state.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_grid/rewards_grid.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_topbar.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// My Rewards body: the member's redemption history over the per-member chrome.
class MyRewardsBody extends StatelessWidget {
  const MyRewardsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.reward),
      child: SingleChildScrollView(
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
