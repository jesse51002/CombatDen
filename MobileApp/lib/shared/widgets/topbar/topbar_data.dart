import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/topbar/app_topbar.dart';

/// Everything a shell topbar layout needs, gathered once so the four
/// layouts share one payload instead of repeating nine parameters.
///
/// Every layout receives the SAME data. A layout may change where these
/// land and how prominent they are; it may not drop one, add one, or
/// reach for anything not in here.
class TopbarData {
  const TopbarData({
    required this.mode,
    required this.showBackButton,
    required this.gymName,
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    required this.onTitleTap,
    this.onTitleDoubleTap,
  });

  final AppTopbarMode mode;
  final bool showBackButton;
  final String gymName;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;
  final VoidCallback onTitleTap;
  final VoidCallback? onTitleDoubleTap;
}
