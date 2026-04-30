import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// One of the four gym-type tiles inside [GymTypeCard].
///
/// When [selected], renders with a full-strength text border and full
/// opacity icon; otherwise the border + icon + label drop to the
/// 50% text color used as a "muted" state across the design.
class GymTypeOption extends StatelessWidget {
  final String label;
  final String iconAsset;
  final bool selected;
  final VoidCallback? onTap;

  const GymTypeOption({
    super.key,
    required this.label,
    required this.iconAsset,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? DesignConstants.text
        : DesignConstants.text3rd;
    final labelColor = selected
        ? DesignConstants.text
        : DesignConstants.text3rd;

    return InkWell(
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.paddingBig,
          horizontal: DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor,
            width: DesignConstants.buttonBorder,
          ),
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusBig,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Opacity(
              opacity: selected ? 1.0 : 0.5,
              child: SizedBox(
                height: 80,
                child: Image.asset(iconAsset, fit: BoxFit.contain),
              ),
            ),
            Text(
              label,
              style: DesignConstants.h2.copyWith(color: labelColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
