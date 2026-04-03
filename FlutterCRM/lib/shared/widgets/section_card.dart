import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A card wrapper with an optional title, used for
/// major content sections.
class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    this.title,
    required this.children,
    this.spacing = DesignConstants.spacingLarge,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.padding = const EdgeInsets.all(
      DesignConstants.paddingBig,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        spacing: spacing,
        children: [
          if (title != null)
            Text(
              title!,
              style: DesignConstants.h1,
            ),
          ...children,
        ],
      ),
    );
  }
}
