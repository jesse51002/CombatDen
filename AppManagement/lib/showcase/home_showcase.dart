import 'package:flutter/material.dart';

import 'package:app_management/showcase/home/home_not_booked_body.dart';
import 'package:app_management/showcase/showcase_content.dart';
import 'package:app_management/showcase/support/showcase_bottom_nav.dart';
import 'package:app_management/showcase/support/showcase_scaffold.dart';
import 'package:app_management/showcase/support/showcase_topbar.dart';

// Dummy non-identity data. Gym name + logo come from the host (arguments);
// these stand in for the streak/points/rank chips in the info bar.
const String _kLogoAsset = 'gym_logo_global_mma.png';
const String _kRankBadgeAsset = 'icon_rank_belt.png';
const int _kStreakDays = 3;
const String _kPointsLabel = '3.4k';

/// Exact visual clone of the member-app **home** screen
/// (`HomeScreen` → `HomeNotBookedBody`): the big-logo topbar, a pinned date
/// strip, and the day-by-day class schedule, under the themed bottom nav.
/// Static surface; [loop] / [onCycleComplete] are accepted for the uniform
/// showcase API but unused. [gymName] / [gymLogo] are the host app's gym
/// identity (NOT a customization slot).
class HomeShowcase extends StatelessWidget {
  const HomeShowcase({
    super.key,
    this.loop = true,
    this.onCycleComplete,
    this.gymName = 'Your Gym',
    this.gymLogo,
    this.classes,
  });

  final bool loop;
  final VoidCallback? onCycleComplete;
  final String gymName;
  final ImageProvider? gymLogo;
  final List<ShowcaseClassInfo>? classes;

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      horizontalPadding: ShowcasePadding.none,
      bottomNav: const ShowcaseBottomNav(selected: ShowcaseNavTab.home),
      child: HomeNotBookedBody(
        classes: classes,
        topbar: ShowcaseTopbar(
          mode: ShowcaseTopbarMode.bigLogo,
          gymName: gymName,
          logoAsset: _kLogoAsset,
          logoImage: gymLogo,
          streakDays: _kStreakDays,
          pointsLabel: _kPointsLabel,
          rankBadgeAsset: _kRankBadgeAsset,
        ),
      ),
    );
  }
}
