import 'package:flutter/material.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/core/selected_gym.dart';
import 'package:mobile_app/features/home/data/mock_gym.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_belt_hero.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_layout_data.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_progress_first.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_sparkle_stack.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_split_rank.dart';
import 'package:mobile_app/features/profile/presentation/layouts/rank_stat_tiles.dart';
import 'package:mobile_app/shared/widgets/nav/app_bottom_nav_bar.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

// Bottom scroll padding to clear the persistent bottom nav.
const double _kBottomScrollPadding = 64;

/// Profile screen — the member's rank and progress.
///
/// The screen owns the frame (scaffold, scroll view, bottom nav) and
/// nothing else: the arrangement of the body is resolved from the
/// tenant's `rank_format` slot and delegated to one of the layouts in
/// `presentation/layouts/`, each of which composes the same elements
/// from the same [RankLayoutData].
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.formatOverride});

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant gate and the preview sheets; null in
  /// normal app use.
  final RankFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      horizontalPadding: AppScreenHorizontalPadding.none,
      bottomNav: const AppBottomNavBar(selected: AppBottomNavTab.rank),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: _kBottomScrollPadding),
        // Local rebuild: switching the format in the dev picker swaps
        // the body in place, without re-keying the tree and losing the
        // screen you are judging.
        child: FormatBuilder(builder: _build),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final data = RankLayoutData(
      profile: mockProfile,
      gymName: selectedGym.displayName,
      logoAsset: mockGym.logoAsset,
    );

    return switch (formatOverride ?? ThemeLayout.rank()) {
      RankFormat.sparkleStack => RankSparkleStack(data: data),
      RankFormat.beltHero => RankBeltHero(data: data),
      RankFormat.statTiles => RankStatTiles(data: data),
      RankFormat.progressFirst => RankProgressFirst(data: data),
      RankFormat.splitRank => RankSplitRank(data: data),
    };
  }
}
