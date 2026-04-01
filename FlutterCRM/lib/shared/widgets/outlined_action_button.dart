import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A full-width outlined button used for actions like
/// "View Waiver", "Promote", "Freeze Membership", etc.
class OutlinedActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const OutlinedActionButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignConstants.text,
          side: const BorderSide(
            color: DesignConstants.buttonStroke,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusSmall,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            vertical:
                DesignConstants.spacingMedium,
          ),
        ),
        child: Text(label, style: DesignConstants.h3),
      ),
    );
  }
}
