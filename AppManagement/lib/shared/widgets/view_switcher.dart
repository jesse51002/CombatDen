import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A row of pill-shaped toggle buttons for switching
/// between views.
///
/// Only one button can be selected at a time.
class ViewSwitcher extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const ViewSwitcher({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: List.generate(labels.length, (index) {
        final isSelected = index == selectedIndex;
        return _ViewButton(
          label: labels[index],
          isSelected: isSelected,
          onTap: () => onSelected(index),
        );
      }),
    );
  }
}

class _ViewButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label view',
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusBig,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingSmall,
            vertical: DesignConstants.spacingMedium,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? DesignConstants.card
                : Colors.transparent,
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
            border: Border.all(
              color: DesignConstants.text,
              width: DesignConstants.buttonBorderSize
            ),
          ),
          child: Text(
            label,
            style: DesignConstants.p.copyWith(
              color: isSelected
                  ? DesignConstants.text
                  : DesignConstants.text2nd,
            ),
          ),
        ),
      ),
    );
  }
}
