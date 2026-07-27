import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/payer_waiver_sign_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_terminal.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// The authorize-a-payer phase, whichever of the two in-run adder dialogs
/// reached it: the agreement still loading, the load that failed, or the
/// agreement itself beside the panel it is signed on.
///
/// Both dialogs end in the same commit against the same waiver, so the phase
/// is one widget rather than two that drift — the version the desk shows is
/// the version the backend version-locks against, and a second copy of this
/// screen is a second chance to show the wrong one.
///
/// It expects a BOUNDED height and takes all of it: the document gets the
/// whole fold and scrolls inside itself.
class AuthorizePayerPane extends StatelessWidget {
  /// The agreement is still being read from the backend.
  final bool fetching;

  /// The read failed. Non-null replaces the pane with the retryable fact.
  final String? error;

  /// The signer, and who they are being authorized to pay for.
  final String payerName;
  final String payeeName;

  final String gymName;

  /// Raw template body of the payee's authorized-payer waiver.
  final String waiverBody;
  final String? waiverName;

  /// A commit in flight freezes the panel rather than replacing it.
  final bool submitting;

  final void Function(String signerName, bool consent) onChanged;

  const AuthorizePayerPane({
    super.key,
    required this.fetching,
    required this.error,
    required this.payerName,
    required this.payeeName,
    required this.gymName,
    required this.waiverBody,
    required this.submitting,
    required this.onChanged,
    this.waiverName,
  });

  @override
  Widget build(BuildContext context) {
    if (fetching) return const Center(child: AppSpinner());
    final failed = error;
    if (failed != null) {
      return SingleChildScrollView(
        child: TaskTerminal(
          icon: Symbols.error_sharp,
          color: DesignConstants.badRed,
          message: failed,
        ),
      );
    }
    return PayerWaiverSignBody(
      payerName: payerName,
      payeeName: payeeName,
      gymName: gymName,
      waiverBody: waiverBody,
      waiverName: waiverName,
      enabled: !submitting,
      fillHeight: true,
      onChanged: onChanged,
    );
  }
}
