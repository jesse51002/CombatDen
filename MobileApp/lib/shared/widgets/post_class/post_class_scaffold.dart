import 'package:flutter/material.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/shared/widgets/post_class/celebration_data.dart';
import 'package:mobile_app/shared/widgets/post_class/layouts/celebration_card_reveal.dart';
import 'package:mobile_app/shared/widgets/post_class/layouts/celebration_center_hero.dart';
import 'package:mobile_app/shared/widgets/post_class/layouts/celebration_figure_top.dart';
import 'package:mobile_app/shared/widgets/post_class/layouts/celebration_full_bleed.dart';
import 'package:mobile_app/shared/widgets/post_class/layouts/celebration_split_band.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/scaffold/app_screen_scaffold.dart';

/// Scaffold for the post-class celebration cards (Streak, Wins, Points,
/// Rewards, Rank). Provides a body area, an optional close (X) action, an
/// optional header, and a full-width primary CTA.
///
/// The public API is unchanged — every screen passes the same arguments
/// it always did. What is new is that the ARRANGEMENT of those four
/// slots is resolved from the tenant's `celebration_format` slot and
/// delegated to one of the layouts in `post_class/layouts/`, each of
/// which composes the same parts from `post_class/parts/`.
///
/// One enum governs all five cards: the [body] differs per card, the
/// arrangement around it does not. A layout may move the slots and
/// change their prominence; it may not drop one, add one, or reach
/// inside [body].
///
/// When a [controller] is supplied, the CTA is hidden (and its taps are
/// ignored) while the controller reports `isAnimating == true`. Tapping
/// anywhere on the body area during that window calls
/// [PostClassController.requestSkip], which the body widget should turn
/// into a jump-to-final-state. Once the body calls
/// [PostClassController.markDone] the CTA fades back in. Every layout
/// gets that contract by construction, because it lives in
/// `CelebrationCta` and `CelebrationStage`.
class PostClassScaffold extends StatelessWidget {
  const PostClassScaffold({
    super.key,
    required this.body,
    required this.ctaLabel,
    required this.onCtaPressed,
    this.header,
    this.onClose,
    this.controller,
    this.formatOverride,
  });

  final Widget body;
  final String ctaLabel;
  final VoidCallback onCtaPressed;
  final Widget? header;
  final VoidCallback? onClose;
  final PostClassController? controller;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the format preview; null in
  /// normal app use.
  final CelebrationFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    return AppScreenScaffold(
      // Each layout owns its own insets: `splitBand` and `fullBleed`
      // need the canvas edge, and `centerHero` re-applies the standard
      // screen padding so it renders exactly as it always has.
      horizontalPadding: AppScreenHorizontalPadding.none,
      child: FormatBuilder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final data = CelebrationData(
      body: body,
      ctaLabel: ctaLabel,
      onCtaPressed: onCtaPressed,
      header: header,
      onClose: onClose,
      controller: controller,
    );

    return switch (formatOverride ?? ThemeLayout.celebration()) {
      CelebrationFormat.centerHero => CelebrationCenterHero(data: data),
      CelebrationFormat.figureTop => CelebrationFigureTop(data: data),
      CelebrationFormat.cardReveal => CelebrationCardReveal(data: data),
      CelebrationFormat.splitBand => CelebrationSplitBand(data: data),
      CelebrationFormat.fullBleed => CelebrationFullBleed(data: data),
    };
  }
}
