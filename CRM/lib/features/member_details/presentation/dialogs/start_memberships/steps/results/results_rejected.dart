import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// C6 — the attempt produced no per-membership breakdown at all, and why.
///
/// Four genuinely different facts about the payer's money, and they must never
/// collapse into "it failed": one never left the device, one was replayed by
/// the backend with the original charge standing, one had nothing left to
/// send, and one went out and was never confirmed. Only the last two of those
/// four can honestly claim nothing was charged.
///
/// Neutral tone, not [EmptyStateTone.error]: red is this flow's hard-validation
/// colour, and none of these is the payer's fault.
class WizardResultsRejected extends StatelessWidget {
  final MembershipWizardCommitError error;

  const WizardResultsRejected({super.key, required this.error});

  /// Whether "nothing was created and nothing was charged" is TRUE for
  /// [error]. It is the head's subtitle, so it is only ever printed where it
  /// is a fact: an unconfirmed attempt may have taken money, and a replayed
  /// one certainly did.
  static bool statesNothingCharged(MembershipWizardCommitError error) =>
      error == MembershipWizardCommitError.failed ||
      error == MembershipWizardCommitError.nothingToSend;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Symbols.warning_sharp,
      title: switch (error) {
        MembershipWizardCommitError.unconfirmed =>
          WizardResultsCopy.unconfirmedTitle,
        MembershipWizardCommitError.alreadyStarted =>
          WizardResultsCopy.alreadyStartedTitle,
        MembershipWizardCommitError.nothingToSend =>
          WizardResultsCopy.nothingToSendTitle,
        MembershipWizardCommitError.failed => WizardResultsCopy.failedTitle,
      },
      body: switch (error) {
        MembershipWizardCommitError.unconfirmed =>
          WizardResultsCopy.unconfirmedBody,
        MembershipWizardCommitError.alreadyStarted =>
          WizardResultsCopy.alreadyStartedBody,
        MembershipWizardCommitError.nothingToSend =>
          WizardResultsCopy.nothingToSendBody,
        MembershipWizardCommitError.failed => WizardResultsCopy.failedBody,
      },
    );
  }
}
