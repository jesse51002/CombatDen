import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_title.dart';

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
  ///
  /// The button callbacks receive the **dialog's own**
  /// `BuildContext` and must pop with
  /// `Navigator.of(dialogContext).pop(value)` — never the
  /// caller's context. The dialog is pushed on the root
  /// navigator (`showDialog`'s default); popping via the
  /// caller's context would target whatever navigator is
  /// nearest the caller (e.g. the nested workspace
  /// navigator the nav rail lives in) and pop the wrong
  /// route instead of the dialog.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget body,
    required String primaryLabel,
    void Function(BuildContext dialogContext)? primaryOnPressed,
    Color? primaryColor,
    String? secondaryLabel = 'Cancel',
    void Function(BuildContext dialogContext)? secondaryOnPressed,
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
          primaryOnPressed: primaryOnPressed == null
              ? null
              : () => primaryOnPressed(dialogContext),
          primaryColor: primaryColor,
          secondaryLabel: secondaryLabel,
          secondaryOnPressed: secondaryOnPressed == null
              ? null
              : () => secondaryOnPressed(dialogContext),
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
