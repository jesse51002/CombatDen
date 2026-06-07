import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Placeholder dialog for an action whose backend is part
/// of the unfinished 25% of the merged contract — there is
/// no frozen bloc event (or no contract-backed endpoint) to
/// drive it yet. Rather than invent an event, the action's
/// affordance opens this so the surface stays complete and
/// the gap is honest.
class ComingSoonDialog {
  ComingSoonDialog._();

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: title,
        body: _Body(message: message),
        actions: AppDialogActions(
          primaryLabel: 'Got it',
          primaryOnPressed: () =>
              Navigator.of(dialogContext).pop(),
          secondaryLabel: null,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Icon(
          Symbols.construction_sharp,
          size: DesignConstants.iconSizeLarge,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.okYellow,
        ),
        Expanded(
          child: Text(
            message,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
        ),
      ],
    );
  }
}
