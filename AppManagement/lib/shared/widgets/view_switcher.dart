import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Full-width underline tabs for switching between top-level views — the
/// standard pattern for primary section nav (Stripe / Linear / GitHub).
/// Equal-width tabs share a hairline baseline; the active tab is marked
/// by a brand-colored underline and brighter, heavier label.
class ViewSwitcher extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Label size. Defaults to [DesignConstants.pBig]; weight and color are
  /// set per tab from its active state.
  final TextStyle? textStyle;

  const ViewSwitcher({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (index) {
        return Expanded(
          child: _Tab(
            label: labels[index],
            isSelected: index == selectedIndex,
            textStyle: textStyle ?? DesignConstants.pBig,
            onTap: () => onSelected(index),
          ),
        );
      }),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final TextStyle textStyle;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.isSelected,
    required this.textStyle,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingMedium,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignConstants.spacingSmall,
                vertical: DesignConstants.spacingMedium,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle.copyWith(
                  color: isSelected
                      ? DesignConstants.text
                      : DesignConstants.text2nd,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            Container(
              height: DesignConstants.buttonBorderSize,
              color: isSelected
                  ? DesignConstants.primaryColor
                  : DesignConstants.divider,
            ),
          ],
        ),
      ),
    );
  }
}
