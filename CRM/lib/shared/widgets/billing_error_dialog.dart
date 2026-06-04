import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Shared error reporter for a failed billing / account
/// mutation. Centralised so every failed action surfaces
/// the same treatment — a reassurance line ("nothing was
/// charged"), the raw backend message in a muted block, and
/// a Retry / OK action — instead of dying silently in a log.
///
/// A reusable billing primitive. The member-detail billing
/// dialogs (a later workflow) call [show] in their catch
/// blocks; pass [onRetry] to offer a re-attempt.
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
        body: _Body(message: message),
        actions: AppDialogActions(
          primaryLabel: onRetry != null ? 'Retry' : 'OK',
          primaryOnPressed: () {
            Navigator.of(dialogContext).pop();
            onRetry?.call();
          },
          secondaryLabel: onRetry != null ? 'Dismiss' : null,
          secondaryOnPressed: () =>
              Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String message;

  const _Body({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              Symbols.error_sharp,
              size: DesignConstants.iconSizeLarge,
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
            color: DesignConstants.backgroundColor,
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
    );
  }
}
