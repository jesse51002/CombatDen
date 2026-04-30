import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/app_primary_button.dart';

/// Footer row for an [AppDialog]. Renders an optional
/// destructive outline button pinned to the left, an
/// optional secondary outline button, and a primary
/// button on the right.
class AppDialogActions extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback? primaryOnPressed;
  final Color? primaryColor;
  final bool isLoading;

  final String? secondaryLabel;
  final VoidCallback? secondaryOnPressed;

  final String? destructiveLabel;
  final VoidCallback? destructiveOnPressed;

  const AppDialogActions({
    super.key,
    required this.primaryLabel,
    this.primaryOnPressed,
    this.primaryColor,
    this.isLoading = false,
    this.secondaryLabel,
    this.secondaryOnPressed,
    this.destructiveLabel,
    this.destructiveOnPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (destructiveLabel != null)
          AppOutlineButton(
            text: destructiveLabel!,
            onPressed: destructiveOnPressed,
            borderRadius: DesignConstants.radiusSmall,
            borderColor: DesignConstants.badRed,
            textStyle: DesignConstants.h3.copyWith(
              color: DesignConstants.badRed,
            ),
          ),
        const Spacer(),
        if (secondaryLabel != null)
          AppOutlineButton(
            text: secondaryLabel!,
            onPressed: secondaryOnPressed ??
                () => Navigator.of(context).pop(),
            borderRadius: DesignConstants.radiusSmall,
          ),
        AppPrimaryButton(
          text: primaryLabel,
          onPressed: primaryOnPressed,
          isLoading: isLoading,
          backgroundColor: primaryColor,
          borderRadius: DesignConstants.radiusSmall,
        ),
      ],
    );
  }
}
