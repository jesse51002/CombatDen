import 'package:flutter/material.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_roster_row.dart';

/// One roster row, wired to the two controls it owns: the membership check,
/// and the remove that takes somebody out of the RUN rather than off the
/// roster.
///
/// The untick commits on the tap — a confirm dialog on a control this cheap is
/// a second trap for whoever already mis-tapped — so the check states the
/// consequence BEFORE it is used, and only when there is something to lose. A
/// warning nobody needs is the fastest way to teach staff to ignore the ones
/// that matter. What was actually dropped is stated after the fact by the
/// step's own consequence notice.
class WhoRosterRow extends StatelessWidget {
  final MembershipWizardPerson person;
  final FlowPersonView view;
  final bool isGroup;
  final MembershipWizardCubit cubit;

  const WhoRosterRow({
    super.key,
    required this.person,
    required this.view,
    required this.isGroup,
    required this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    final consequence = cubit.consequenceOfUntick(person.memberId);
    final warns = view.training && (consequence?.destroys ?? false);
    return FlowRosterRow(
      person: view,
      isGroup: isGroup,
      // Never fires: the view is built with `editable: false`, so the row
      // draws no Edit at all.
      onDetails: () {},
      onRemove: () => cubit.setTraining(person.memberId, false),
      onTrainingChanged: (on) => cubit.setTraining(person.memberId, on),
      checkNote: warns ? WizardWhoCopy.untickNote(person.firstName) : null,
    );
  }
}
