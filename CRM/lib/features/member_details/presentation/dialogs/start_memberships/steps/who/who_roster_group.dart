import 'package:flutter/material.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who/who_roster_row.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_views.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// The merged roster — one row per person this payer may cover, hairline
/// separated inside the step's single panel.
///
/// It is the FIRST group in the panel, so it carries no eyebrow: the step's
/// own title already names it.
class WhoRosterGroup extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardCubit cubit;

  const WhoRosterGroup({
    super.key,
    required this.state,
    required this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    final people = state.people;
    final isGroup = people.length > 1;
    return FlowDetailGroup(
      children: [
        for (var i = 0; i < people.length; i++) ...[
          if (i > 0) const Hairline(),
          WhoRosterRow(
            person: people[i],
            // Which affordances the row may offer is the SEAM's decision, not
            // this widget's — `wizard_views.dart` is where the desk's reading
            // of a person lives, and a second opinion here is how the two
            // surfaces started disagreeing in the first place.
            view: wizardRosterPerson(state, people[i]),
            isGroup: isGroup,
            cubit: cubit,
          ),
        ],
      ],
    );
  }
}
