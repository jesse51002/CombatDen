import 'package:flutter/material.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/customization/data/models/customization_style.dart';
import 'package:mobile_app/features/style_select/presentation/widgets/style_card/style_card.dart';

/// Vertical list of selectable styles. Large celebration images read
/// better stacked than in a tight grid.
class StyleList extends StatelessWidget {
  const StyleList({
    super.key,
    required this.styles,
    required this.activeId,
    required this.onSelect,
  });

  final List<CustomizationStyle> styles;
  final String? activeId;
  final ValueChanged<CustomizationStyle> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final style in styles)
          StyleCard(
            style: style,
            isActive: style.id == activeId,
            onTap: () => onSelect(style),
          ),
      ],
    );
  }
}
