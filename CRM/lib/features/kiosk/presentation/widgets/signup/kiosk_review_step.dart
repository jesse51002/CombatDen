import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_money_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_review_group_panel.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_review_side_panel.dart';
import 'package:crm/shared/widgets/app_spinner.dart';

/// D6 — the last screen before the money moves: what was picked, what was
/// signed, what comes off the card today and what happens next month.
///
/// The preview behind it is a real server-side staging of the whole request (it
/// builds the rows and asks Stripe), which is why it can fail and why a failure
/// gets its own retryable stop rather than a blank panel.
///
/// The escape CONFIRMS here, and says "Start over", never "Cancel" — beside
/// `Sign Membership · $149.00`, "Cancel" reads as *cancel the payment*.
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
        return FlowStepScaffold(
          step: KioskSignupStep.review,
          // Button-agnostic: the label below says what is being signed and for
          // how much, so naming it here would start lying the moment a trial
          // cart changes the verb.
          title: 'Check this over',
          subtitle: state.isGroup
              ? 'One card covers everyone. Nothing is charged until you '
                  'confirm.'
              : 'Nothing is charged until you confirm.',
          foot: FlowFoot(
            primaryLabel: _primaryLabel(state, ready: ready),
            // The label carries the amount, so the button is inert until the
            // amount is real: never commit before the screen says what for.
            onPrimary: ready ? cubit.pay : null,
            onBack: cubit.back,
            confirmAbandon: true,
          ),
          child: ready ? _Panels(state: state) : const _Loading(),
        );
      },
    );
  }

  /// The committing button reads by WHAT is being bought, then by how much:
  /// "Sign Trial" only when every training person's pick is a trial, "Sign
  /// Membership" otherwise (a mixed group cart is a membership purchase taken
  /// as a whole), pluralised when more than one person is buying.
  ///
  /// The amount stays on the button because a trial is a plan CATEGORY, not a
  /// price — a gym can sell a paid two-week trial — so a bare verb on a button
  /// that takes money would be a real omission. It collapses to the bare verb
  /// when there is nothing to charge.
  String _primaryLabel(KioskSignupState state, {required bool ready}) {
    final plural = state.trainingPersonIndexes.length > 1;
    final noun = state.cartAllTrial
        ? (plural ? 'Trials' : 'Trial')
        : (plural ? 'Memberships' : 'Membership');
    final verb = 'Sign $noun';
    final due = state.dueTodayMinorUnits;
    if (!ready || due <= 0) return verb;
    return '$verb · ${formatMinorUnits(due, currency: state.currency)}';
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
              // A group is blocked BY PERSON — the solo panel reads as a single
              // purchase and cannot answer "who costs what" for a family.
              child: state.isGroup
                  ? FlowReviewGroupPanel(state: state)
                  : FlowReviewSidePanel(state: state),
            ),
            Expanded(
              child: FlowMoneyPanel(
                state: state,
                contactEmail: state.payer.email,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
