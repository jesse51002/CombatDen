import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One de-carded metric section: its title, its measurement window, and
/// the renderer body beneath them.
///
/// The renderers draw bodies only — this is the chrome around them. Nothing
/// here is boxed in a card; sections are separated by whitespace and a
/// hairline, per the page's De-Card rule.
class GrowthSection extends StatelessWidget {
  /// The metric's display name.
  final String title;

  /// The window the numbers cover ("Last 30 days"). Empty or null hides
  /// the line rather than printing a blank one.
  final String? subtitle;

  final Widget child;

  const GrowthSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(title, style: DesignConstants.h2),
            if (sub != null && sub.isNotEmpty)
              Text(
                sub,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
          ],
        ),
        child,
      ],
    );
  }
}
