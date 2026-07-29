import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/shared/widgets/topbar/layouts/topbar_compact_rail.dart';
import 'package:mobile_app/shared/widgets/topbar/layouts/topbar_mark_only.dart';
import 'package:mobile_app/shared/widgets/topbar/layouts/topbar_stacked.dart';
import 'package:mobile_app/shared/widgets/topbar/layouts/topbar_stat_first.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_data.dart';

/// Per-screen prominence hint for the gym identity.
///
/// * [bigLogo] — large square gym logo above the gym name. Home only.
/// * [nameOnly] — just the gym name + chevron. Every other screen.
///
/// This stays a SCREEN-level choice and is unchanged. The tenant-level
/// choice is `AppShellFormat`, which decides how the whole shell is
/// arranged; each layout honours this hint in its own way.
enum AppTopbarMode { bigLogo, nameOnly }

/// Shared page topbar.
///
/// The public API is unchanged — every screen passes the same nine
/// arguments it always did. What is new is that the arrangement is
/// resolved from the tenant's `app_shell_format` slot and delegated to
/// one of the layouts in `topbar/layouts/`, each of which composes the
/// same parts from `topbar/parts/`.
///
/// Every layout receives the identical [TopbarData] and must render
/// every element in it: mark, name, switch chevron, rank badge, streak,
/// points, and the QR action. A layout may move them and change their
/// prominence. It may not drop one or add one.
class AppTopbar extends StatelessWidget {
  const AppTopbar({
    super.key,
    required this.mode,
    required this.showBackButton,
    required this.gymName,
    required this.logoAsset,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    this.onTitleTap,
    this.onTitleDoubleTap,
    this.formatOverride,
  });

  final AppTopbarMode mode;
  final bool showBackButton;
  final String gymName;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the format preview; null in
  /// normal app use.
  final AppShellFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return FormatBuilder(builder: _build);
  }

  Widget _build(BuildContext context) {
    final data = TopbarData(
      mode: mode,
      showBackButton: showBackButton,
      gymName: gymName,
      logoAsset: logoAsset,
      streakDays: streakDays,
      pointsLabel: pointsLabel,
      rankBadgeAsset: rankBadgeAsset,
      onTitleTap: () => _handleTitleTap(context),
      onTitleDoubleTap: onTitleDoubleTap,
    );

    return switch (formatOverride ?? ThemeLayout.shell()) {
      AppShellFormat.stacked => TopbarStacked(data: data),
      AppShellFormat.compactRail => TopbarCompactRail(data: data),
      AppShellFormat.statFirst => TopbarStatFirst(data: data),
      AppShellFormat.markOnly => TopbarMarkOnly(data: data),
    };
  }

  void _handleTitleTap(BuildContext context) {
    if (onTitleTap != null) {
      onTitleTap!();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (r) => false,
    );
  }
}
