import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Error reporter for failed billing / account mutations.
/// Centralised so every failed action surfaces the same
/// treatment instead of silently dying in a log.
class BillingErrorDialog {
  BillingErrorDialog._();

  static Future<void> show({
    required BuildContext context,
    required String message,
    String title = 'Something went wrong',
    VoidCallback? onRetry,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: title,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Icon(
                  Symbols.error_sharp,
                  size: 24,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.badRed,
                ),
                Expanded(
                  child: Text(
                    'The action did not complete. '
                    'Nothing was charged or changed.',
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                DesignConstants.spacingMedium,
              ),
              decoration: BoxDecoration(
                color: DesignConstants.card,
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
              ),
              child: Text(
                message,
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ],
        ),
        actions: AppDialogActions(
          primaryLabel: onRetry != null ? 'Retry' : 'OK',
          primaryColor: onRetry != null
              ? DesignConstants.primaryColor
              : DesignConstants.card,
          primaryOnPressed: () {
            Navigator.of(dialogContext).pop();
            onRetry?.call();
          },
          secondaryLabel:
              onRetry != null ? 'Dismiss' : null,
          secondaryOnPressed: () =>
              Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }
}
