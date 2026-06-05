import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The "Add New … +" row shown under a catalog table (mirrors
/// the mockup's centered add-row affordance). Tapping it opens
/// the same create dialog as the top-right primary button.
class AddRowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const AddRowButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingLarge,
        ),
        child: Center(
          child: Text(
            '$label +',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text3rd,
            ),
          ),
        ),
      ),
    );
  }
}
