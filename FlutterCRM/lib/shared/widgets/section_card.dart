import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A card wrapper with an optional title, used for
/// major content sections.
class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SectionCard({
    super.key,
    this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: DesignConstants.spacingLarge,
      ),
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.cardBackground,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: DesignConstants.h2,
            ),
            const SizedBox(
              height:
                  DesignConstants.spacingMedium,
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}
