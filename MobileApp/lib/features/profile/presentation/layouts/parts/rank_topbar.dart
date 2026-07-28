import 'package:flutter/material.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// The rank screen's topbar, built from [RankLayoutData].
///
/// One place so all five arrangements pass identical arguments — the
/// shell's own format decides how the bar is drawn, and the rank format
/// never touches it.
class RankTopbar extends StatelessWidget {
  const RankTopbar({super.key, required this.data});

  final RankLayoutData data;

  @override
  Widget build(BuildContext context) {
    return AppTopbar(
      mode: AppTopbarMode.nameOnly,
      showBackButton: false,
      gymName: data.gymName,
      logoAsset: data.logoAsset,
      streakDays: data.profile.streakDays,
      pointsLabel: data.profile.pointsLabel,
      rankBadgeAsset: data.profile.rankBadgeAsset,
    );
  }
}
