import 'package:flutter/material.dart';
import 'package:mobile_app/features/rewards/presentation/layouts/rewards_layout_data.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The points store's topbar, built from [RewardsLayoutData] so every
/// format passes the identical arguments. Its own arrangement is the
/// tenant's `app_shell_format` decision, not this screen's.
class RewardsTopbar extends StatelessWidget {
  const RewardsTopbar({super.key, required this.data});

  final RewardsLayoutData data;

  @override
  Widget build(BuildContext context) {
    return AppTopbar(
      mode: AppTopbarMode.nameOnly,
      showBackButton: false,
      gymName: data.gymName,
      logoAsset: data.logoAsset,
      streakDays: data.streakDays,
      pointsLabel: data.pointsLabel,
      rankBadgeAsset: data.rankBadgeAsset,
    );
  }
}
