import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The create-a-person footer: Cancel on the left, then the TWO ways to
/// commit — "Create & invite" and "Create without inviting" — in the same
/// three-slot shape `DuplicateFooter` uses.
///
/// The two commits are rendered with the SAME [AppPrimaryButton] treatment on
/// purpose. There is no pre-selected default and no checkbox, because a
/// default is what gets clicked through: creating a row provisions nothing, so
/// whether the person is told is a real question staff must answer. Neither is
/// styled as a warning — not inviting is a perfectly ordinary choice (a
/// walk-in with no email, a hire who is told in person).
///
/// When [canInvite] is false there is nobody to invite (no email was entered),
/// so the question collapses to a single plain "Create" — asking it would be
/// noise.
///
/// The two commits sit in an [OverflowBar] so they stack instead of
/// overflowing in the narrow `dialogMaxWidth` surface (both labels side by
/// side need ~684px; the Add-employee dialog has 480). Stacked, they keep the
/// identical treatment — only their order differs, which is the least the
/// layout can give away.
class CreateInviteActions extends StatelessWidget {
  /// What the commit is called, e.g. `'Create'` → "Create & invite" /
  /// "Create without inviting", and the lone button when [canInvite] is false.
  final String createLabel;

  /// Fired with whether an invite was asked for.
  final ValueChanged<bool> onCreate;

  final VoidCallback onCancel;

  /// False when no email has been entered — there is nobody to invite.
  final bool canInvite;

  /// A create POST is in flight: everything is inert and the invite commit
  /// (or the lone commit) shows the spinner.
  final bool busy;

  const CreateInviteActions({
    super.key,
    required this.onCreate,
    required this.onCancel,
    this.createLabel = 'Create',
    this.canInvite = true,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!canInvite) {
      return AppDialogActions(
        primaryLabel: createLabel,
        isLoading: busy,
        primaryOnPressed: busy ? null : () => onCreate(false),
        secondaryLabel: 'Cancel',
        secondaryOnPressed: busy ? null : onCancel,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        AppOutlineButton(
          text: 'Cancel',
          onPressed: busy ? null : onCancel,
          borderRadius: DesignConstants.radiusSmall,
        ),
        Expanded(
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: DesignConstants.spacingMedium,
            overflowSpacing: DesignConstants.spacingMedium,
            children: [
              AppPrimaryButton(
                text: '$createLabel without inviting',
                onPressed: busy ? null : () => onCreate(false),
                borderRadius: DesignConstants.radiusSmall,
              ),
              AppPrimaryButton(
                text: '$createLabel & invite',
                onPressed: busy ? null : () => onCreate(true),
                isLoading: busy,
                borderRadius: DesignConstants.radiusSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
