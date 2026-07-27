import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/shared/widgets/topbar/info_bar.dart';
import 'package:mobile_app/shared/widgets/topbar/topbar_header_section.dart';

/// Visual mode for [AppTopbar], matching the two variants in the
/// `topbar` master component.
///
/// * [bigLogo] — large square gym logo above the gym name. Used on the home
///   screen.
/// * [nameOnly] — just the centered gym name. Used on every other screen that
///   shows the topbar.
///
/// Both variants carry the member's avatar in the trailing flank.
enum AppTopbarMode { bigLogo, nameOnly }

/// Shared page topbar used across the app. Mirrors the `topbar`
/// component variants exactly: [AppTopbarMode.bigLogo] /
/// [AppTopbarMode.nameOnly] crossed with an optional [showBackButton].
class AppTopbar extends StatelessWidget {
  const AppTopbar({
    super.key,
    required this.mode,
    required this.showBackButton,
    required this.gymName,
    required this.logoAsset,
    this.gymLogoUrl,
    required this.streakDays,
    required this.pointsLabel,
    required this.rankBadgeAsset,
    this.rankImageUrl,
    this.showRank = true,
    this.pointsSpendable = true,
    this.memberName,
    this.memberPhotoUrl,
    this.memberFirstName,
    this.memberLastName,
    this.onTitleTap,
    this.onTitleDoubleTap,
    this.onQrTap,
  });

  final AppTopbarMode mode;
  final bool showBackButton;
  final String gymName;
  final String logoAsset;

  /// The gym's own uploaded logo (`gyms.logo_url`), preferred over the
  /// theme's mark in the [AppTopbarMode.bigLogo] variant.
  final String? gymLogoUrl;
  final int streakDays;
  final String pointsLabel;
  final String rankBadgeAsset;

  /// The member's OWN rank art (`MemberProfile.rank?.imageUrl`), threaded to
  /// the [InfoBar]'s belt. Every wrapper passes it from the shared
  /// `MemberProfileBloc`; null (no profile loaded yet, ranks off, or a rank
  /// with no image) leaves the themed/bundled belt in place.
  final String? rankImageUrl;

  /// Whether the gym runs a rank ladder (`selectedMember.gymRankEnabled`).
  /// False collapses the [InfoBar]'s belt tile on every topbar.
  final bool showRank;

  /// Whether the gym has rewards (`selectedMember.gymHasRewards`). False makes
  /// the [InfoBar]'s points tile a read-out instead of a link into the store.
  final bool pointsSpendable;

  /// The selected member's display name — the accessibility label on the
  /// trailing identity avatar. The avatar renders either way.
  final String? memberName;

  /// The selected member's photo + name parts, driving the trailing identity
  /// avatar (photo, else initials, else a person glyph).
  final String? memberPhotoUrl;
  final String? memberFirstName;
  final String? memberLastName;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;

  /// Optional QR-tile tap handler, threaded to the [InfoBar]. Only the home
  /// topbar wires it (to open the check-in scanner); every other topbar leaves
  /// it null, so its QR tile stays a static icon.
  final VoidCallback? onQrTap;

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
            gymLogoUrl: gymLogoUrl,
            memberName: memberName,
            memberPhotoUrl: memberPhotoUrl,
            memberFirstName: memberFirstName,
            memberLastName: memberLastName,
            onTitleTap: () => _handleTitleTap(context),
            onTitleDoubleTap: onTitleDoubleTap,
          ),
          InfoBar(
            rankBadgeAsset: rankBadgeAsset,
            rankImageUrl: rankImageUrl,
            showRank: showRank,
            pointsSpendable: pointsSpendable,
            streakDays: streakDays,
            pointsLabel: pointsLabel,
            onQrTap: onQrTap,
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
    Navigator.of(context).pushNamed(AppRoutes.memberSelect);
  }
}
