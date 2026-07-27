import 'package:flutter/foundation.dart';

/// Everything a step can ask for that only the HOST can do: open a nested
/// staff dialog, leave the run, or navigate somewhere else in the app.
///
/// It is one object passed down rather than eight callbacks threaded through
/// each step, and it is deliberately NOT on the cubit: every one of these
/// needs a `BuildContext` and a `Navigator`, which is exactly what a cubit
/// must not hold. The cubit owns what the run KNOWS; this owns what the room
/// around it can do.
@immutable
class WizardActions {
  /// Leave the run. Nothing is charged and nothing is created.
  final VoidCallback close;

  /// Close the run and open that member's own page — the results receipt's
  /// per-row jump, and the only navigation the wizard performs.
  final ValueChanged<String> viewMember;

  /// Create somebody new and authorize the payer for them, then add them to
  /// the run.
  final VoidCallback addNewMember;

  /// Find an existing member and authorize the payer for them.
  final VoidCallback linkMember;

  /// Change who pays. It rebuilds the roster, so the control states that
  /// before it is used.
  final VoidCallback changePayer;

  /// Add or replace the PAYER's saved default card.
  final VoidCallback updateSavedCard;

  /// Capture a one-off card for a purely one-time cart.
  final VoidCallback captureOneOffCard;

  const WizardActions({
    required this.close,
    required this.viewMember,
    required this.addNewMember,
    required this.linkMember,
    required this.changePayer,
    required this.updateSavedCard,
    required this.captureOneOffCard,
  });
}
