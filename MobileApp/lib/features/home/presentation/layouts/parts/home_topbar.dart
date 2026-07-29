import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// Home's topbar, wired once.
///
/// Every home format renders exactly this — same mode, same gym data,
/// same double-tap into the gym picker. The topbar's own arrangement is
/// the tenant's `app_shell_format`, not home's, so no home layout has
/// any business changing what it is handed.
class HomeTopbar extends StatelessWidget {
  const HomeTopbar({super.key});

  @override
  Widget build(BuildContext context) {
    final gym = mockGym;
    return AppTopbar(
      mode: AppTopbarMode.bigLogo,
      showBackButton: false,
      gymName: selectedGym.displayName,
      logoAsset: gym.logoAsset,
      streakDays: gym.streakDays,
      pointsLabel: gym.pointsLabel,
      rankBadgeAsset: gym.rankBadgeAsset,
      onTitleDoubleTap: () =>
          Navigator.of(context).pushNamed(AppRoutes.styleSelect),
    );
  }
}
