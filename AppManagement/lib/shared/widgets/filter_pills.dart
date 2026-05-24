import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A wrapping row of compact, single-select filter pills. Lighter than
/// [ViewSwitcher] (which is for top-level views) — sized for many
/// options like a feed's category filters.
class FilterPills extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const FilterPills({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignConstants.spacingSmall,
      runSpacing: DesignConstants.spacingSmall,
      children: [
        for (var i = 0; i < labels.length; i++)
          _Pill(
            label: labels[i],
            isSelected: i == selectedIndex,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? DesignConstants.primaryColor
              : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        child: Text(
          label,
          style: DesignConstants.pBig.copyWith(
            color: isSelected ? DesignConstants.text : DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
