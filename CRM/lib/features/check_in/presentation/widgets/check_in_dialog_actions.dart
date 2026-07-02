import 'package:flutter/material.dart';

import 'package:crm/shared/widgets/app_dialog/app_dialog_actions.dart';

/// Shared [AppDialog] footers for the check-in dialogs. The processing phase
/// has no footer (the caller returns null); these cover the others.

/// Terminal "Done" footer that dismisses the dialog.
AppDialogActions checkInDoneActions(BuildContext context) => AppDialogActions(
      primaryLabel: 'Done',
      primaryOnPressed: () => Navigator.of(context).pop(),
    );

/// A primary action over a dismiss button (the dismiss pops via the default).
/// Drives the pick/select step ("Check in"), the needs-confirmation step
/// ("Check in anyway"), and the error step ("Try again"). A null [onPrimary]
/// disables the primary (nothing selected yet).
AppDialogActions checkInChoiceActions({
  required String primaryLabel,
  required VoidCallback? onPrimary,
  required String dismissLabel,
}) =>
    AppDialogActions(
      primaryLabel: primaryLabel,
      primaryOnPressed: onPrimary,
      secondaryLabel: dismissLabel,
    );
