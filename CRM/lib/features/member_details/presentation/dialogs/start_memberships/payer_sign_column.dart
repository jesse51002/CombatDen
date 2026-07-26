import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/constants/esign_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/sign_outcome_notice.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_person_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/task_chrome/task_note.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_sign_panel.dart';

/// The signing half of the authorized-payer agreement: who is putting their
/// name to it, the typed legal name, the consent tick, what signing will DO,
/// and the electronic-records disclosure that binds it.
///
/// The banner names the PAYER, never the payee — a panel reading "SIGNING FOR
/// Ella" while the payer types their own name would be wrong about who is
/// bound, and this is the one waiver in the app whose signer is not its
/// subject.
///
/// The green outcome sits under the tick rather than after the commit: the
/// consequence of authorizing somebody else's bill is the thing a payer is
/// deciding, so it is on screen while they decide.
class PayerSignColumn extends StatelessWidget {
  /// The signer — the party being bound.
  final String payerName;

  /// Who the payer is being authorized to pay for.
  final String payeeName;

  final TextEditingController signerName;
  final ValueChanged<String> onSignerNameChanged;

  final bool consent;
  final ValueChanged<bool> onConsentChanged;

  const PayerSignColumn({
    super.key,
    required this.payerName,
    required this.payeeName,
    required this.signerName,
    required this.onSignerNameChanged,
    required this.consent,
    required this.onConsentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        FlowSignPanel(
          memberName: payerName,
          eyebrow: StartPersonCopy.signEyebrow,
          bannerNote: StartPersonCopy.signBannerNote(payeeName),
          consentLabel: StartPersonCopy.signConsentLabel,
          consentNote: StartPersonCopy.signConsentNote,
          signerName: signerName,
          onSignerNameChanged: onSignerNameChanged,
          consent: consent,
          onConsentChanged: onConsentChanged,
        ),
        SignOutcomeNotice(
          message: StartPersonCopy.signOutcome(payerName, payeeName),
        ),
        // The ESIGN/UETA disclosure the signature is recorded under. It stays
        // on this screen: the backend stamps its version onto the signature
        // row, so a signer who never saw it would be pinned to text they were
        // not shown.
        const TaskNote(kEsignDisclosure),
      ],
    );
  }
}
