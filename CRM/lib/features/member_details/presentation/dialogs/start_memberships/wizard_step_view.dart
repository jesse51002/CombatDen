import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/plans_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/results_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/review_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/waivers_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/who_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';

/// The one place the cubit's step becomes a screen.
///
/// A switch over a sealed enum rather than a map, so a step added to the spine
/// cannot ship without a screen — the old wizard's body was a chain of `if`s
/// whose fall-through was an empty box.
class WizardStepView extends StatelessWidget {
  /// The add-member tail prepends an always-done rung to every step's rail.
  final bool showAddMemberGroup;

  final WizardActions actions;

  const WizardStepView({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        return switch (state.step) {
          MembershipWizardStep.who => WizardWhoStep(
              showAddMemberGroup: showAddMemberGroup,
              actions: actions,
            ),
          MembershipWizardStep.plans => WizardPlansStep(
              showAddMemberGroup: showAddMemberGroup,
              actions: actions,
            ),
          MembershipWizardStep.waivers => WizardWaiversStep(
              showAddMemberGroup: showAddMemberGroup,
              actions: actions,
            ),
          MembershipWizardStep.reviewCharges => WizardReviewStep(
              showAddMemberGroup: showAddMemberGroup,
              actions: actions,
            ),
          MembershipWizardStep.payment => WizardPaymentStep(
              showAddMemberGroup: showAddMemberGroup,
              actions: actions,
            ),
          MembershipWizardStep.results => WizardResultsStep(
              showAddMemberGroup: showAddMemberGroup,
              actions: actions,
            ),
        };
      },
    );
  }
}
