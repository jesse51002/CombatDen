import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// "Is this you?" — the person who started this signup already has an account
/// here, and it carries no payment method, so it may be adopted.
///
/// **Why showing it is not a leak.** They typed this exact name and this exact
/// email one screen ago; the card confirms their OWN account back to them and
/// masks the address exactly as the payee match card does. It is reached only
/// after the no-attached-card gate has answered — a card on file, or a check
/// that did not answer, lands on the terminal stop instead and the match is
/// never rendered at all.
///
/// The card carries no "you typed" half: for a payee the comparison is the
/// point (is this the same Ella?), while here both halves would be the same
/// person and the second box would only add noise.
class KioskPayerMatchStep extends StatelessWidget {
  const KioskPayerMatchStep({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.matchCandidate != cur.matchCandidate ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final match = state.matchCandidate;
        if (match == null) return const SizedBox.shrink();
        return KioskSignupStepScaffold(
          step: KioskSignupStep.payerMatch,
          title: 'Is this you?',
          subtitle: 'You already have an account here. If it\'s you, we\'ll '
              'use it instead of making a second one.',
          foot: const KioskFlowFoot(onPrimary: null),
          child: KioskSignupFormPanel(
            children: [
              KioskMatchCard(match: match),
              _Decide(busy: state.submitting),
            ],
          ),
        );
      },
    );
  }
}

/// The two answers, centred under the card they are about. "No" is the
/// terminal front-desk stop — the same one an ineligible match lands on.
class _Decide extends StatelessWidget {
  final bool busy;

  const _Decide({required this.busy});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return IntrinsicWrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        KioskOutlineButton(
          text: 'No, that\'s not me',
          onPressed: busy ? null : cubit.declinePayerMatch,
        ),
        KioskPrimaryButton(
          text: 'Yes, that\'s me',
          onPressed: busy ? null : cubit.confirmPayerMatch,
        ),
      ],
    );
  }
}
