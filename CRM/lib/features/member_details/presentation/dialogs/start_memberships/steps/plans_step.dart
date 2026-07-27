import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_empty_body.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_identity_strip.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans/plans_stage.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_scaffold.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Step 2 — one training person's memberships, walked once per person.
///
/// Everything the old flow spread over `plans → discounts` per person happens
/// here: a pick becomes a card that owns its own pack count, its live price
/// and its own discounts. That is what takes the run from `6 + 2N` screens to
/// `5 + N`.
class WizardPlansStep extends StatefulWidget {
  final bool showAddMemberGroup;
  final WizardActions actions;

  const WizardPlansStep({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  State<WizardPlansStep> createState() => _WizardPlansStepState();
}

class _WizardPlansStepState extends State<WizardPlansStep> {
  /// The answer a blocked tap opened, pinned to the person it was asked
  /// about — so the next person's grid never inherits the last one's reason.
  ({String memberId, String message})? _blocked;

  void _explain(
    MembershipWizardPerson person,
    MembershipPlanResponse plan,
  ) {
    setState(() {
      _blocked = (
        memberId: person.memberId,
        message: WizardPlansCopy.blockedNote(person.firstName, plan.planName),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembershipWizardCubit>();
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        final copy = MembershipFlowTheme.copyOf(context);
        final people = state.trainingPeople;
        final person = state.currentPerson;
        final stage = plansStageOf(state, person);
        // Non-null exactly on the screen that HAS a person to be about.
        final active = stage == PlansStage.grid ? person : null;
        return WizardStepScaffold(
          step: MembershipWizardStep.plans,
          hasWaivers: state.hasWaivers,
          showAddMemberGroup: widget.showAddMemberGroup,
          title: copy.planStepTitle(
            firstName: person?.firstName ?? '',
            isGroup: people.length > 1,
          ),
          // The answering line counts the run's people; a screen with no grid
          // on it has no turn to count.
          subtitle: active == null
              ? null
              : copy.planStepSubtitle(
                  personIndex: people.indexOf(active),
                  personCount: people.length,
                ),
          identity: active == null
              ? null
              : PlansIdentityStrip(
                  payerName: state.payer.name,
                  personName: active.name,
                  personIsPayer: active.memberId == state.payer.memberId,
                ),
          foot: PlansFoot(
            state: state,
            cubit: cubit,
            stage: stage,
            person: person,
            onEscape: widget.actions.close,
          ),
          child: active == null
              ? _Stateless(stage: stage, onRetry: cubit.loadCatalogue)
              : PlansBody(
                  state: state,
                  cubit: cubit,
                  memberId: active.memberId,
                  firstName: active.firstName,
                  blockedNote: _blocked?.memberId == active.memberId
                      ? _blocked?.message
                      : null,
                  onBlocked: (plan) => _explain(active, plan),
                ),
        );
      },
    );
  }
}

/// The four screens with no catalogue on them. Each states the fact and, where
/// there is one, the way out.
class _Stateless extends StatelessWidget {
  final PlansStage stage;
  final VoidCallback onRetry;

  const _Stateless({required this.stage, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return switch (stage) {
      PlansStage.failed => PlansFailedBody(onRetry: onRetry),
      PlansStage.noPlans => const PlansEmptyBody(),
      PlansStage.nobody => const PlansNobodyBody(),
      PlansStage.loading || PlansStage.grid => const _Waiting(),
    };
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(child: AppSpinner()),
    );
  }
}
