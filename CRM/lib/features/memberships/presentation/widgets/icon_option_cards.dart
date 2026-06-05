import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One option in an [IconOptionCards] selector.
class IconOption {
  final IconData icon;
  final String label;

  /// Optional secondary line under the label (e.g. "Billed monthly").
  final String? subtitle;

  const IconOption({
    required this.icon,
    required this.label,
    this.subtitle,
  });
}

/// A prominent row of selectable icon + label cards (the
/// Membership Type and Entitlement selectors both use this).
/// The selected card is outlined in the brand color; cards are
/// equal height via [IntrinsicHeight].
class IconOptionCards extends StatelessWidget {
  final List<IconOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const IconOptionCards({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: List.generate(options.length, (i) {
          return Expanded(
            child: _Card(
              option: options[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          );
        }),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconOption option;
  final bool selected;
  final VoidCallback onTap;

  const _Card({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.paddingBig,
          horizontal: DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.line,
            width: DesignConstants.buttonBorderSize,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              option.icon,
              size: DesignConstants.iconSizeBig,
              weight: DesignConstants.iconWeight,
              color: selected
                  ? DesignConstants.primaryColor
                  : DesignConstants.text2nd,
            ),
            Text(
              option.label,
              textAlign: TextAlign.center,
              style: DesignConstants.h3.copyWith(
                color: selected
                    ? DesignConstants.text
                    : DesignConstants.text2nd,
              ),
            ),
            if (option.subtitle != null)
              Text(
                option.subtitle!,
                textAlign: TextAlign.center,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
