import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// A modal, non-dismissible loading popup: a spinner + message shown
/// while a short operation runs (e.g. bridging the gap between two
/// dialogs so the screen never looks idle). Open with [LoadingDialog.show]
/// and close it with [LoadingDialog.dismiss].
class LoadingDialog extends StatelessWidget {
  final String message;

  const LoadingDialog({super.key, this.message = 'Loading…'});

  /// Push a non-dismissible loading popup on the root navigator.
  static void show(BuildContext context, {String message = 'Loading…'}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialog(message: message),
    );
  }

  /// Pop the loading popup (the topmost root route).
  static void dismiss(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DesignConstants.popup,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingLarge,
          children: [
            const AppSpinner(),
            Text(message, style: DesignConstants.p),
          ],
        ),
      ),
    );
  }
}
