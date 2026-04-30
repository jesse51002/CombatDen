import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// "Add Filter +" pill — a thin outlined button that sits just below
/// the search row. Visual-only no-op for the prototype.
class MembersFilterButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MembersFilterButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: DesignConstants.text2nd,
        side: BorderSide(
          color: DesignConstants.text2nd,
          width: DesignConstants.buttonBorder,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingBig,
          vertical: DesignConstants.spacingSmall,
        ),
      ),
      child: Text(
        'Add Filter +',
        style: DesignConstants.h2.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}
