import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Footer actions for the class form: optional secondary "Cancel a date range"
/// and destructive "Delete" (both edit mode only) on the left, then the form's
/// Cancel and Save aligned right.
class ClassFormActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;

  /// Soft-delete the class; null in create mode (the button is then hidden).
  final VoidCallback? onDelete;

  /// Open the cancel-a-date-range dialog; null in create mode (a class must
  /// exist before its occurrences can be cancelled — the button is hidden).
  final VoidCallback? onCancelRange;

  const ClassFormActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.onDelete,
    this.onCancelRange,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingLarge,
      children: [
        if (onCancelRange != null)
          AppOutlineButton(
            text: 'Cancel a date range',
            onPressed: onCancelRange,
          ),
        if (onDelete != null)
          AppOutlineButton(
            text: 'Delete',
            onPressed: onDelete,
            borderColor: DesignConstants.badRed,
            textColor: DesignConstants.badRed,
          ),
        const Spacer(),
        AppOutlineButton(text: 'Cancel', onPressed: onCancel),
        AppPrimaryButton(
          text: 'Save Class',
          onPressed: onSave,
          textStyle: DesignConstants.h2,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
            vertical: DesignConstants.spacingMedium,
          ),
        ),
      ],
    );
  }
}
