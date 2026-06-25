import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

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
    // IntrinsicWrap, not Wrap: pills sit inside IntrinsicHeight-driven
    // layouts (member-detail grid) and must report run-aware height.
    return IntrinsicWrap(
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

/// A wrapping row of compact, **multi-select** filter pills. Same look as
/// [FilterPills] (white + hairline when off, sapphire fill + white label
/// when on), but any number of pills can be lit at once — for filter
/// dialogs where the user picks several statuses / plans.
class MultiSelectPills extends StatelessWidget {
  final List<String> labels;
  final Set<int> selectedIndices;
  final ValueChanged<int> onToggled;

  const MultiSelectPills({
    super.key,
    required this.labels,
    required this.selectedIndices,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWrap(
      spacing: DesignConstants.spacingSmall,
      runSpacing: DesignConstants.spacingSmall,
      children: [
        for (var i = 0; i < labels.length; i++)
          _Pill(
            label: labels[i],
            isSelected: selectedIndices.contains(i),
            onTap: () => onToggled(i),
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
          border: isSelected
              ? null
              : Border.all(color: DesignConstants.line),
        ),
        child: Text(
          label,
          style: DesignConstants.pBig.copyWith(
            color: isSelected
                ? DesignConstants.onAccent
                : DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
