import 'package:flutter/material.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The class screen's topbar, defined once for all five layouts.
///
/// Shared rather than repeated so no arrangement can quietly ship a
/// different topbar — or lose the back control, which is the only way
/// off this screen that does not commit to a booking.
class ClassScreenTopbar extends StatelessWidget {
  const ClassScreenTopbar({super.key});

  @override
  Widget build(BuildContext context) {
    final gym = mockGym;
    return AppTopbar(
      mode: AppTopbarMode.nameOnly,
      showBackButton: true,
      gymName: selectedGym.displayName,
      logoAsset: gym.logoAsset,
      streakDays: gym.streakDays,
      pointsLabel: gym.pointsLabel,
      rankBadgeAsset: gym.rankBadgeAsset,
    );
  }
}
