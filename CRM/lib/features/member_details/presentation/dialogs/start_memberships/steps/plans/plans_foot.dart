import 'package:flutter/material.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_stage.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/wizard_foot_note.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';

/// The plans step's decision band, and the line above it naming why the
/// primary is unavailable.
///
/// Skip is GROUP-only: it works by unticking the person, so skipping the sole
/// person of a run would empty the cart entirely — at least one person has to
/// be getting a membership for there to be a run at all.
class PlansFoot extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardCubit cubit;
  final PlansStage stage;
  final MembershipWizardPerson? person;
  final VoidCallback onEscape;

  const PlansFoot({
    super.key,
    required this.state,
    required this.cubit,
    required this.stage,
    required this.person,
    required this.onEscape,
  });

  @override
  Widget build(BuildContext context) {
    final active = stage == PlansStage.grid ? person : null;
    final note = _note(active);
    final skippable = active != null && state.trainingPeople.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note != null) WizardFootNote(text: note),
        FlowFoot(
          onPrimary: state.canAdvance ? cubit.next : null,
          onBack: cubit.canGoBack ? cubit.back : null,
          onSkip: skippable
              ? () => cubit.setTraining(active.memberId, false)
              : null,
          skipLabel: active == null
              ? null
              : WizardPlansCopy.skipPerson(active.firstName),
          onEscape: onEscape,
        ),
      ],
    );
  }

  String? _note(MembershipWizardPerson? active) => switch (stage) {
        PlansStage.failed => WizardPlansCopy.plansFailedFoot,
        PlansStage.noPlans => WizardPlansCopy.noPlansFoot,
        PlansStage.nobody => WizardPlansCopy.nobodyFoot,
        PlansStage.loading => null,
        PlansStage.grid => state.canAdvance || active == null
            ? null
            : WizardPlansCopy.needAPlan(active.firstName),
      };
}
