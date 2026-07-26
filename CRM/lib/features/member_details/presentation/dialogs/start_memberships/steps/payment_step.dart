import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/network/stripe_account_context.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_cubit.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment/payment_card_unavailable.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment/payment_one_off_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment/payment_saved_card_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/payment/payment_totals_group.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/steps/shared/wizard_step_foot.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_actions.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_step_scaffold.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_consent_check.dart';

/// Frame 8 — how this run settles, asked AFTER the charges so nobody chooses a
/// method before seeing what it costs.
///
/// Three ways to pay, each stating its own consequence: cash explains what
/// happens to future cycles, the saved card warns that replacing it re-bills
/// every recurring membership this payer holds, and the one-off card is
/// blocked rather than hidden. C4 — a gym whose Stripe account cannot take a
/// card — replaces both card groups with a warm block and leaves cash open, so
/// the run is still completable today.
class WizardPaymentStep extends StatelessWidget {
  final bool showAddMemberGroup;
  final WizardActions actions;

  const WizardPaymentStep({
    super.key,
    required this.showAddMemberGroup,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MembershipWizardCubit>();
    return BlocBuilder<MembershipWizardCubit, MembershipWizardState>(
      builder: (context, state) {
        // Rebuilds when the connected account resolves or a gym switch
        // re-applies it, so C4 appears and clears on its own.
        return ListenableBuilder(
          listenable: stripeAccountContext,
          builder: (context, _) {
            final copy = MembershipFlowTheme.copyOf(context);
            // Not-yet-resolved is a momentary state, not a failure: only a
            // RESOLVED context with no usable account is card entry being down.
            final cardEntryDown = stripeAccountContext.isReady &&
                !stripeAccountContext.paymentsAvailable;
            final dueToday = formatMinorUnits(
              state.dueTodayMinor,
              currency: state.currency,
            );
            return WizardStepScaffold(
              step: MembershipWizardStep.payment,
              hasWaivers: state.hasWaivers,
              showAddMemberGroup: showAddMemberGroup,
              title: copy.paymentStepTitle,
              subtitle: WizardPaymentCopy.settlesToday(dueToday),
              identity: FlowWhoFor(
                eyebrow: copy.payingEyebrow,
                name: state.payer.name,
              ),
              foot: WizardStepFoot(
                note: state.canAdvance
                    ? null
                    : cardEntryDown
                        ? WizardPaymentCopy.cashOnly
                        : WizardPaymentCopy.needSettlement,
                onEscape: actions.close,
                onBack: cubit.canGoBack ? cubit.back : null,
                primaryLabel: WizardPaymentCopy.pay(dueToday),
                onPrimary: state.canAdvance ? cubit.pay : null,
              ),
              child: _Body(
                state: state,
                cubit: cubit,
                actions: actions,
                cardEntryDown: cardEntryDown,
              ),
            );
          },
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final MembershipWizardState state;
  final MembershipWizardCubit cubit;
  final WizardActions actions;
  final bool cardEntryDown;

  const _Body({
    required this.state,
    required this.cubit,
    required this.actions,
    required this.cardEntryDown,
  });

  @override
  Widget build(BuildContext context) {
    return FlowFormPanel(
      children: [
        // First group, so no eyebrow: the step's own title names it.
        FlowDetailGroup(
          children: [
            FlowConsentCheck(
              value: state.paidWithCash,
              onChanged: cubit.setPaidWithCash,
              label: WizardPaymentCopy.cashLabel,
              note: WizardPaymentCopy.cashNote(state.payer.firstName),
            ),
          ],
        ),
        if (cardEntryDown)
          WizardPaymentCardUnavailable(
            payerFirstName: state.payer.firstName,
            hasSavedCard: state.savedCard != null,
          )
        else ...[
          // Nothing goes on a card at all while cash is ticked, so the card
          // that would have paid is not offered.
          if (!state.paidWithCash)
            WizardPaymentSavedCardGroup(
              payerFirstName: state.payer.firstName,
              card: state.savedCard,
              onUpdateCard: actions.updateSavedCard,
            ),
          WizardPaymentOneOffGroup(
            card: state.customCard,
            block: state.oneOffCardBlock,
            onCapture: actions.captureOneOffCard,
            onRemove: cubit.clearCustomCard,
          ),
        ],
        WizardPaymentTotalsGroup(
          state: state,
          cardLast4: _settlingLast4(state),
        ),
      ],
    );
  }
}

/// The last four of the card that will ACTUALLY settle today — the one-off
/// where it is what pays, the saved default otherwise, and nothing at all on a
/// cash run. Naming the wrong card here is naming the wrong charge.
String? _settlingLast4(MembershipWizardState state) {
  if (state.paidWithCash) return null;
  if (state.oneOffCardPays) return state.customCard?.lastFour;
  return state.savedCard?.lastFour;
}
