import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_step_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// "Is this you?" — the person who started this signup already has an account
/// here, and it carries no payment method, so it may be adopted.
///
/// Not a leak: on both routes (they typed this exact name and email one screen
/// ago, or they tapped it out of the search themselves) the card confirms their
/// OWN account back to them, masked. Both routes still get a confirm — two
/// members can share a name, and a mis-tap on a shared iPad would seat a
/// stranger's account behind the card about to be typed.
class KioskPayerMatchStep extends StatelessWidget {
  const KioskPayerMatchStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.matchCandidate != cur.matchCandidate ||
          prev.payerMatchFromIdentify != cur.payerMatchFromIdentify ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final match = state.matchCandidate;
        if (match == null) return const SizedBox.shrink();
        // Kiosk-only step: the desk never confronts the payer with their own
        // duplicate, so this head lives on the kiosk's own copy. The route it
        // was reached by is the fact the answering line branches on.
        final copy = kioskStepCopy(context);
        return KioskStepScaffold(
          step: KioskSignupStep.payerMatch,
          title: copy.payerMatchStepTitle,
          subtitle: copy.payerMatchStepSubtitle(
            fromIdentify: state.payerMatchFromIdentify,
          ),
          foot: FlowFoot(onPrimary: null, onEscape: cubit.abandon),
          child: FlowFormPanel(
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

/// The two answers, centred under the card they are about.
///
/// "No" goes back where the match came from: the identify search after a
/// mis-tapped name, the terminal front-desk stop when the create was already
/// refused and the kiosk has nothing else to offer.
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
