import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';

/// Multi-select waiver picker — a plan can require several waivers.
/// Renders the gym's waivers as toggle chips.
class WaiverMultiSelect extends StatelessWidget {
  final List<WaiverResponse> waivers;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const WaiverMultiSelect({
    super.key,
    required this.waivers,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (waivers.isEmpty) {
      return Text(
        'No waivers yet — add one in the Waivers tab.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      );
    }
    return Wrap(
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        for (final waiver in waivers)
          _WaiverChip(
            label: waiver.name,
            selected: selectedIds.contains(waiver.waiverId),
            onTap: () => onToggle(waiver.waiverId),
          ),
      ],
    );
  }
}

class _WaiverChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WaiverChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? DesignConstants.primaryColor
        : DesignConstants.text2nd;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          color: selected
              ? DesignConstants.primaryColor.withValues(alpha: 0.08)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingSmall,
          children: [
            Icon(
              selected ? Symbols.check_sharp : Symbols.add_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: color,
            ),
            Text(label, style: DesignConstants.p.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
