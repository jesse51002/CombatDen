import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_money_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_group_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_review_side_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// D6 — the last screen before the money moves.
///
/// It shows what was picked, what was signed, exactly what comes off the card
/// today and what happens next month. The preview behind it is a real
/// server-side staging of the whole request (it builds the rows and asks
/// Stripe), which is why it can fail and why a failure gets its own retryable
/// stop rather than a blank panel.
///
/// The escape CONFIRMS here: the button sits beside a money button at the most
/// anxious moment in the flow, and it says "Start over", never "Cancel" —
/// beside `Pay $149.00`, "Cancel" reads as *cancel the payment*.
class KioskReviewStep extends StatelessWidget {
  const KioskReviewStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.preview != cur.preview ||
          prev.previewLoading != cur.previewLoading ||
          prev.signedWaivers != cur.signedWaivers ||
          prev.persons != cur.persons ||
          prev.cardLast4 != cur.cardLast4,
      builder: (context, state) {
        final ready = state.preview != null;
        // The velocity cooldown after a run of declines lives on the decline
        // popup, big and central — never here. A member can never reach this
        // screen while cooling (try-again is gated on the popup until it
        // elapses), so the Pay button carries only the amount. `pay()` still
        // refuses while `retryCooldown > 0` as the belt-and-suspenders guard.
        return KioskSignupStepScaffold(
          step: KioskSignupStep.review,
          title: 'Check this over',
          subtitle: state.isGroup
              ? 'One card covers everyone. Nothing is charged until you tap '
                  'Pay.'
              : 'Nothing is charged until you tap Pay.',
          foot: KioskFlowFoot(
            primaryLabel: ready
                ? 'Pay ${formatMinorUnits(
                    state.dueTodayMinorUnits,
                    currency: state.currency,
                  )}'
                : 'Pay',
            // The label carries the amount, so the button is inert until the
            // amount is real — a member must never be able to tap "Pay" before
            // the screen can tell them what for.
            onPrimary: ready ? cubit.pay : null,
            onBack: cubit.back,
            confirmAbandon: true,
          ),
          child: ready ? _Panels(state: state) : const _Loading(),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(DesignConstants.paddingBig),
      child: Center(child: AppSpinner()),
    );
  }
}

class _Panels extends StatelessWidget {
  final KioskSignupState state;

  const _Panels({required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesignConstants.kioskFormMeasure,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(
              // A group's left half is blocked BY PERSON (the solo panel's
              // "YOU / YOUR MEMBERSHIP" reads as a single purchase and cannot
              // answer "who costs what" for a family).
              child: state.isGroup
                  ? KioskReviewGroupPanel(state: state)
                  : KioskReviewSidePanel(state: state),
            ),
            Expanded(
              child: KioskMoneyPanel(
                state: state,
                receiptEmail: state.payer.email,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
