import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';

/// Thin wrapper around [AppDialog] for the common
/// "title + single message + confirm/cancel" pattern.
class ConfirmationModal {
  ConfirmationModal._();

  /// Shows the confirmation dialog and returns true if
  /// the user tapped the confirm button, false otherwise.
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
    String cancelLabel = 'Cancel',
  }) async {
    final result = await AppDialog.show<bool>(
      context: context,
      title: title,
      body: Text(
        message,
        style: DesignConstants.p.copyWith(
          color: DesignConstants.text2nd,
        ),
      ),
      primaryLabel: confirmLabel,
      primaryColor: confirmColor,
      primaryOnPressed: () =>
          Navigator.of(context).pop(true),
      secondaryLabel: cancelLabel,
      secondaryOnPressed: () =>
          Navigator.of(context).pop(false),
    );
    return result ?? false;
  }
}
