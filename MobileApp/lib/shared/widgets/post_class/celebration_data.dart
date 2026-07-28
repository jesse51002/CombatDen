import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

/// Everything a celebration layout needs, gathered once so the five
/// layouts share one payload instead of repeating six parameters.
///
/// Every layout receives the SAME data and must render every slot in it:
/// the close action (where the screen supplies one), the header (where
/// the screen supplies one), the body, and exactly one primary CTA. A
/// layout may move them and change their prominence. It may not drop
/// one, add one, or reach for anything not in here — in particular it
/// cannot reach INSIDE [body], which is one opaque widget per card.
class CelebrationData {
  const CelebrationData({
    required this.body,
    required this.ctaLabel,
    required this.onCtaPressed,
    this.header,
    this.onClose,
    this.controller,
  });

  /// The card's own content: hero illustration, count-up figure, caption
  /// and any supporting detail, as one widget. Opaque to every layout.
  final Widget body;

  final String ctaLabel;
  final VoidCallback onCtaPressed;
  final Widget? header;
  final VoidCallback? onClose;

  /// Drives the intro contract: while `isAnimating` the CTA is hidden and
  /// a tap on the stage means "skip".
  final PostClassController? controller;
}
