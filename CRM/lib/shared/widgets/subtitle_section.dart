import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A reusable section with an h2-styled subtitle and content
/// below it.
class SubtitleSection extends StatelessWidget {
  final String title;
  final Widget child;

  const SubtitleSection({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(title, style: DesignConstants.h2),
        child,
      ],
    );
  }
}
