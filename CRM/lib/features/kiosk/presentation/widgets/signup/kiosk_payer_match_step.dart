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
/// **Why showing it is not a leak.** Either they typed this exact name and
/// email one screen ago (the duplicate route) or they tapped it themselves out
/// of the search (the identify route). The card confirms their OWN account
/// back to them and masks the address exactly as the payee match card does.
///
/// A confirm is warranted on both routes even though the identify one tapped
/// their own name: two members can share a name, and a mis-tap on a shared
/// iPad would seat a stranger's account behind the card about to be typed.
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
          prev.payerMatchFromIdentify != cur.payerMatchFromIdentify ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final match = state.matchCandidate;
        if (match == null) return const SizedBox.shrink();
        return KioskSignupStepScaffold(
          step: KioskSignupStep.payerMatch,
          title: 'Is this you?',
          // On the identify route they just told us they have an account, so
          // saying it back is redundant; on the duplicate route it is the
          // news.
          subtitle: state.payerMatchFromIdentify
              ? 'Tap yes and we\'ll use this account. Nothing new gets '
                  'created.'
              : 'You already have an account here. If it\'s you, we\'ll use '
                  'it instead of making a second one.',
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

/// The two answers, centred under the card they are about.
///
/// "No" goes where the match came from: back to the identify search when they
/// simply mis-tapped a name, and to the terminal front-desk stop when the
/// create was already refused and there is nothing else the kiosk can do.
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
