import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A panel with the standard `DesignConstants.card` background and
/// `radiusBig` corners. Used as the chrome around major dashboard
/// regions (Live Attendance, Upcoming Classes, Revenue Card).
///
/// Adapted from `FlutterCRM/lib/shared/widgets/section_card.dart` —
/// kept minimal because the prototype rarely needs the title slot.
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignConstants.paddingBig),
    this.borderRadius = DesignConstants.radiusBig,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? DesignConstants.card,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}
