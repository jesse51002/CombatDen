import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/core/navigation/app_routes.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_header_section.dart';

/// Visual mode for [AppTopbar], matching the two variants in the Figma
/// `topbar` master component (node `288:581`).
///
/// * [bigLogo] — large square gym logo above the gym name and chevron-down.
///   Used on the home screen.
/// * [nameOnly] — just the centered gym name + chevron-down. Used on every
///   other screen that shows the topbar.
enum AppTopbarMode { bigLogo, nameOnly }

/// Shared page topbar used across the app. Mirrors the Figma `topbar`
/// component variants exactly: [AppTopbarMode.bigLogo] /
/// [AppTopbarMode.nameOnly] crossed with an optional [showBackButton].
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
  });

  final AppTopbarMode mode;
  final bool showBackButton;
  final String gymName;
  final String logoAsset;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: DesignConstants.text3rd,
            width: DesignConstants.dividerThickness,
          ),
        ),
      ),
      padding: EdgeInsets.only(
        top: DesignConstants.spacingBig,
        bottom: DesignConstants.spacingLarge,
        left: DesignConstants.spacingMedium,
        right: DesignConstants.spacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          TopbarHeaderSection(
            mode: mode,
            showBackButton: showBackButton,
            gymName: gymName,
            logoAsset: logoAsset,
            onTitleTap: () => _handleTitleTap(context),
          ),
          InfoBar(
            rankBadgeAsset: rankBadgeAsset,
            streakDays: streakDays,
            pointsLabel: pointsLabel,
          ),
        ],
      ),
    );
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
