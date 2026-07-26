import 'package:flutter/material.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/wizard_foot_note.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';

/// The roster step's decision band.
///
/// The primary counts the people it carries forward, so staff read the size of
/// the run off the button rather than the roster. There is no Back — this is
/// step one — and the escape says `Cancel` rather than the surface's own
/// `Start over`: nothing has been started yet to start over from, and the
/// control leaves the run entirely.
class WhoFoot extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardCubit cubit;
  final VoidCallback onEscape;

  const WhoFoot({
    super.key,
    required this.state,
    required this.cubit,
    required this.onEscape,
  });

  void _advance() {
    cubit.clearConsequence();
    cubit.next();
  }

  @override
  Widget build(BuildContext context) {
    final note = state.payerLoad.isFailed
        ? WizardWhoCopy.loadFailedFoot
        : state.canAdvance
            ? null
            : WizardWhoCopy.needSomebody;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note != null) WizardFootNote(text: note),
        FlowFoot(
          // Leaving the step forward answers the consequence notice: it is a
          // statement about the roster being left behind, and it must not be
          // waiting on the way back in.
          onPrimary: state.canAdvance ? _advance : null,
          primaryLabel:
              WizardWhoCopy.continueWith(state.trainingPeople.length),
          onEscape: onEscape,
          escapeLabel: WizardChromeCopy.cancelRun,
        ),
      ],
    );
  }
}
