import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// Footer actions for the class form: Cancel and Save, aligned right.
class ClassFormActions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const ClassFormActions({
    super.key,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: DesignConstants.spacingLarge,
      children: [
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
