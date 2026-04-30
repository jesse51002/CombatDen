import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:app_management/shared/widgets/app_dialog/app_dialog_title.dart';

/// Shared popup shell used for every dialog in the app.
///
/// Owns the common chrome: popup background,
/// small-radius corners, max width, padding, title row,
/// body slot, and an optional actions row with a primary
/// + optional secondary button.
class AppDialog extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? actions;
  final bool showCloseButton;

  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showCloseButton = true,
  });

  /// Convenience builder that wires up a standard
  /// primary (+ optional secondary) footer and returns
  /// the value popped by [primaryOnPressed].
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget body,
    required String primaryLabel,
    VoidCallback? primaryOnPressed,
    Color? primaryColor,
    String? secondaryLabel = 'Cancel',
    VoidCallback? secondaryOnPressed,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => AppDialog(
        title: title,
        body: body,
        actions: AppDialogActions(
          primaryLabel: primaryLabel,
          primaryOnPressed: primaryOnPressed,
          primaryColor: primaryColor,
          secondaryLabel: secondaryLabel,
          secondaryOnPressed: secondaryOnPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DesignConstants.popup,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.paddingSmall,
        vertical: DesignConstants.paddingBig,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(
            DesignConstants.paddingSmall,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              AppDialogTitle(
                title: title,
                showCloseButton: showCloseButton,
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: body,
                ),
              ),
              ?actions,
            ],
          ),
        ),
      ),
    );
  }
}
