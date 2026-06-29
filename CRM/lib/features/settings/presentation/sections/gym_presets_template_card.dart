import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/presets/data/models/preset_models.dart';

/// One selectable template card in the gym-presets picker.
///
/// Text-only: the template name, its disciplines, and a compact
/// "N videos · classes · rewards" hint. A selected card gets a sapphire border +
/// accent background overlay.
class GymPresetsTemplateCard extends StatelessWidget {
  final TemplateCard template;
  final bool isSelected;
  final VoidCallback onTap;

  const GymPresetsTemplateCard({
    super.key,
    required this.template,
    required this.isSelected,
    required this.onTap,
  });

  static const double _cardWidth = 180.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _cardWidth,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(
            color: isSelected ? DesignConstants.primaryColor : DesignConstants.line,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected ? DesignConstants.buttonShadow : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignConstants.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                template.displayName,
                style: DesignConstants.h3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (template.gymType.isNotEmpty)
                Text(
                  _disciplines(template.gymType),
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              _HintRow(template: template),
            ],
          ),
        ),
      ),
    );
  }

  static String _disciplines(List<String> types) => types
      .take(2)
      .map((t) => t.split('_').map(_cap).join(' '))
      .join(', ');

  static String _cap(String w) =>
      w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}';
}

class _HintRow extends StatelessWidget {
  final TemplateCard template;

  const _HintRow({required this.template});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      '${template.videoCount} videos',
      if (template.hasClasses) 'classes',
      if (template.hasRewards) 'rewards',
    ];
    return Text(
      parts.join(' · '),
      style: DesignConstants.pSmall.copyWith(
        color: DesignConstants.text2nd,
      ),
    );
  }
}
