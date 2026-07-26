import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/refresh/app_refresh.dart';
import 'package:mobile_app/core/refresh/refresh_signal.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_bloc.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_event.dart';
import 'package:mobile_app/features/rewards/bloc/rewards_state.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/points_headline.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_load_status.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_tabs.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/rewards_topbar.dart';
import 'package:mobile_app/features/rewards/presentation/widgets/store_grid/store_grid.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/nav/nav_tabs.dart';
import 'package:mobile_app/shared/widgets/refresh/app_refresh_view.dart';
import 'package:mobile_app/shared/widgets/refresh/selected_member_scope.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Points Store body: the live catalog grid over the per-member chrome. A
/// redeem success bumps the [RewardsBloc]'s token → this fires
/// `MemberProfileRefreshRequested` (balance + pending refresh) and confirms
/// with a SnackBar; a redeem 4xx surfaces the backend detail as a SnackBar.
class PointsStoreBody extends StatelessWidget {
  const PointsStoreBody({super.key});

  void _onRedeemSuccess(BuildContext context) {
    context
        .read<MemberProfileBloc>()
        .add(const MemberProfileRefreshRequested());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Redemption requested — pending staff approval',
            style: DesignConstants.p,
          ),
        ),
      );
  }

  /// The shared pull: identity + capabilities + branding, theme, the shared
  /// profile (which owns the points balance above), and this screen's catalog
  /// + redemptions — all awaited. The profile leg is the balance refresh, so
  /// nothing here dispatches it a second time.
  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<RewardsBloc>();
    return AppRefresh.forScreen(
      context,
      screen: () => dispatchRefresh(bloc, RewardsRefreshRequested.new),
    );
  }

  void _onRedeemError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message, style: DesignConstants.p)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<RewardsBloc, RewardsState>(
          listenWhen: (p, c) =>
              p.redeemSuccessToken != c.redeemSuccessToken,
          listener: (context, _) => _onRedeemSuccess(context),
        ),
        BlocListener<RewardsBloc, RewardsState>(
          listenWhen: (p, c) =>
              p.redeemError != c.redeemError && c.redeemError != null,
          listener: (context, state) =>
              _onRedeemError(context, state.redeemError!),
        ),
      ],
      child: SelectedMemberScope(
        builder: (context) => AppScreenScaffold(
          horizontalPadding: AppScreenHorizontalPadding.none,
          bottomNav: AppBottomNavBar(
            selected: AppBottomNavTab.reward,
            tabs: gymNavTabs(),
          ),
          child: AppRefreshView(
            onRefresh: () => _refresh(context),
            child: SingleChildScrollView(
              // An empty catalog is shorter than the viewport; without this the
              // page would refuse the drag exactly when a member most wants to
              // retry.
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingBig,
                children: [
                  const RewardsTopbar(),
                  RewardsTabs(
                    active: RewardsTab.pointsStore,
                    onMyRewardsTap: () => Navigator.of(context)
                        .pushReplacementNamed(AppRoutes.myRewards),
                  ),
                  const _PointsHeadlineSection(),
                  const _StoreGridSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "you earned N points" hero, read live from the profile balance.
class _PointsHeadlineSection extends StatelessWidget {
  const _PointsHeadlineSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      builder: (context, state) => PointsHeadline(
        points: state.profile?.retention.pointsBalance ?? 0,
      ),
    );
  }
}

/// The catalog grid with its loading / retry-able error / empty states.
class _StoreGridSection extends StatelessWidget {
  const _StoreGridSection();

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
              state.errorMessage ?? 'Could not load the rewards store.',
              onRetry: () => context
                  .read<RewardsBloc>()
                  .add(const RewardsLoadRequested()),
            );
          case RewardsStatus.loaded:
            if (state.catalog.isEmpty) {
              return const RewardsLoadStatus('No rewards in the store yet.');
            }
            return StoreGrid(items: state.catalog);
        }
      },
    );
  }
}
