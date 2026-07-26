import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_outcome.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/results/results_receipt.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/results/results_rejected.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_step_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_scaffold.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// Frames 9, 10, 11 and C6 — the run's one terminal screen, in whichever of
/// its three states the commit left it.
///
/// The order matters and is not interchangeable. `starting` is the charge in
/// flight. A landed `startResult` is a RECEIPT, whole or partial, and outranks
/// any error that followed it — a failed retry must never erase what an
/// earlier attempt created. Only with no breakdown at all does the commit
/// error become the screen.
///
/// None of the three offers an escape: from the moment PAY is pressed the run
/// may not be abandoned without reading what happened to the money.
class WizardResultsStep extends StatelessWidget {
  final bool showAddMemberGroup;
  final WizardActions actions;

  const WizardResultsStep({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembershipWizardCubit>();
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        final copy = MembershipFlowTheme.copyOf(context);
        if (state.starting) {
          return _scaffold(
            state: state,
            title: WizardResultsCopy.processingTitle,
            subtitle: WizardResultsCopy.processingBody(
              state.pendingItems.length,
              state.payer.name,
            ),
            // Disabled, because there is nothing to do but wait.
            foot: WizardStepFoot(
              onEscape: null,
              primaryLabel: copy.doneAction,
              onPrimary: null,
            ),
            child: const Center(child: AppSpinner()),
          );
        }
        if (state.startResult != null) {
          return _receipt(context, state, cubit);
        }
        // A results step with neither a breakdown nor an error cannot happen
        // through the cubit's own paths; treating it as the plain failure
        // leaves staff on a screen that says so and offers the way back.
        final error =
            state.commitError ?? MembershipWizardCommitError.failed;
        final backToPayment = error == MembershipWizardCommitError.failed ||
            error == MembershipWizardCommitError.nothingToSend;
        return _scaffold(
          state: state,
          title: WizardResultsCopy.rejectedTitle,
          subtitle: WizardResultsRejected.statesNothingCharged(error)
              ? WizardResultsCopy.rejectedSubtitle
              : null,
          foot: WizardStepFoot(
            onEscape: null,
            // A fresh attempt is offered ONLY where nothing can already have
            // been taken. `unconfirmed` is the double-charge latch firing and
            // `alreadyStarted` is a charge that already stands — neither may
            // walk back to a PAY button.
            primaryLabel: backToPayment
                ? WizardResultsCopy.backToPayment
                : copy.doneAction,
            onPrimary: backToPayment
                ? () {
                    cubit.clearCommitError();
                    cubit.enterPayment();
                  }
                : actions.close,
          ),
          child: WizardResultsRejected(error: error),
        );
      },
    );
  }

  Widget _receipt(
    BuildContext context,
    MembershipWizardState state,
    MembershipWizardCubit cubit,
  ) {
    final copy = MembershipFlowTheme.copyOf(context);
    final allCreated = state.outcome == MembershipWizardOutcome.allCreated;
    final settled = state.paidWithCash || state.dueTodayMinor == 0
        ? null
        : formatMinorUnits(state.dueTodayMinor, currency: state.currency);
    return _scaffold(
      state: state,
      title: copy.resultsStepTitle(
        allCreated: allCreated,
        count: state.startItems.length,
      ),
      subtitle: copy.resultsStepSubtitle(
        allCreated: allCreated,
        isGroup: state.people.length > 1,
        amountLabel: settled,
        cardLast4: _settledLast4(state),
      ),
      // Retry is the loud action the mockup gives it — it is what the desk
      // came back for — and Done keeps the quieter mirror gutter. The foot's
      // Back slot is fixed to the flow's own word, so Done cannot ride it.
      foot: WizardStepFoot(
        onEscape: null,
        primaryLabel:
            state.canRetry ? WizardResultsCopy.retry : copy.doneAction,
        onPrimary: state.canRetry ? cubit.retryUncreated : actions.close,
        onSkip: state.canRetry ? actions.close : null,
        skipLabel: state.canRetry ? copy.doneAction : null,
      ),
      child: WizardResultsReceipt(
        state: state,
        onViewMember: actions.viewMember,
      ),
    );
  }

  Widget _scaffold({
    required MembershipWizardState state,
    required String title,
    required String? subtitle,
    required Widget foot,
    required Widget child,
  }) =>
      WizardStepScaffold(
        step: MembershipWizardStep.results,
        hasWaivers: state.hasWaivers,
        showAddMemberGroup: showAddMemberGroup,
        title: title,
        subtitle: subtitle,
        foot: foot,
        child: child,
      );
}

/// The last four of the card the run actually settled on. Null on a cash run
/// and on a run that took nothing.
String? _settledLast4(MembershipWizardState state) {
  if (state.paidWithCash) return null;
  if (state.oneOffCardPays) return state.customCard?.lastFour;
  return state.savedCard?.lastFour;
}
