import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';

/// A reusable section with an h2-styled subtitle and content
/// below it.
class SubtitleSection extends StatelessWidget {
  final String title;
  final Widget child;
  final double spacing;

  const SubtitleSection({
    super.key,
    required this.title,
    required this.child,
    this.spacing = DesignConstants.spacingLarge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: spacing,
      children: [
        Text(title, style: DesignConstants.h2),
        child,
      ],
    );
  }
}
