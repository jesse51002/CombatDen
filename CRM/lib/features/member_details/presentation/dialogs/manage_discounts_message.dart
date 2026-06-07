import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Centred icon + text shown inside the manage-discounts
/// dialog for its empty / load-failed states.
class ManageDiscountsMessage extends StatelessWidget {
  final String text;
  final IconData? icon;

  const ManageDiscountsMessage({
    super.key,
    required this.text,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (icon != null)
          Icon(
            icon,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
          ),
        Flexible(
          child: Text(
            text,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}
