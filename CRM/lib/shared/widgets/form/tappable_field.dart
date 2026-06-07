import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A labeled, read-only field box that opens a picker on tap. Shared shell
/// for [AppDateField] and [AppTimeField]; matches the [CustomTextField]
/// box (card fill, 2px border, rounded corners) with a trailing icon.
class TappableField extends StatelessWidget {
  final String label;
  final String? valueText;
  final String hintText;
  final IconData icon;
  final VoidCallback onTap;

  const TappableField({
    super.key,
    required this.label,
    required this.valueText,
    required this.hintText,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = valueText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: DesignConstants.h2),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          child: Container(
            padding: const EdgeInsets.all(DesignConstants.paddingSmall),
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
              border: Border.all(
                color: DesignConstants.text,
                width: DesignConstants.buttonBorder,
              ),
            ),
            child: Row(
              spacing: DesignConstants.spacingMedium,
              children: [
                Expanded(
                  child: Text(
                    valueText ?? hintText,
                    style: DesignConstants.p.copyWith(
                      color: hasValue
                          ? DesignConstants.text
                          : DesignConstants.text3rd,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  color: DesignConstants.text2nd,
                  weight: DesignConstants.iconWeight,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
