import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Save-time choice for a body edit that forks a SIGNED waiver version:
/// should prior signers re-sign the new version?
///
/// Returns `false` ("Don't require re-signing" — the primary; small fixes
/// are the common case), `true` ("Require re-signing" — the change alters
/// what members agreed to), or `null` when dismissed (the caller aborts
/// the save).
class RequireResignDialog extends StatelessWidget {
  final int signedCount;

  const RequireResignDialog({super.key, required this.signedCount});

  static Future<bool?> show(
    BuildContext context, {
    required int signedCount,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => RequireResignDialog(signedCount: signedCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Require members to re-sign?',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            signedCount > 0
                ? '$signedCount member(s) have signed the current version. '
                    'Saving publishes a new version of the text.'
                : 'No one has signed the current version yet — saving '
                    'updates it in place.',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text,
            ),
          ),
          Text(
            'Require re-signing when the change alters what members '
            'agreed to: everyone who signed before must sign the new '
            'version again before they can buy a membership or check in '
            '(they show as "Needs re-sign" until they do).\n\n'
            'For a small fix that doesn\'t change the meaning — a typo, '
            'formatting — don\'t require it; existing signatures stay '
            'valid.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      ),
      actions: AppDialogActions(
        primaryLabel: "Don't require re-signing",
        primaryOnPressed: () => Navigator.of(context).pop(false),
        secondaryLabel: 'Require re-signing',
        secondaryOnPressed: () => Navigator.of(context).pop(true),
      ),
    );
  }
}
