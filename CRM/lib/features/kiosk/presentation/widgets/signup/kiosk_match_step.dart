import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// E2 — "Is this the same Ella?"
///
/// **The deliberate asymmetry with the payer.** A 409 on the PAYER is a
/// terminal front-desk stop: the kiosk may only charge a card belonging to a
/// member it created in this signup, so "that's me, use my account" cannot
/// exist there and the 409's matches are never even rendered. A 409 on a
/// PAYEE is an OFFER, because a payee pays nothing — reusing their existing
/// account is the correct and desirable outcome.
///
/// Two decisions sit on this screen at different scales and read as different
/// sentences: the panel's "No — different person" corrects WHO this is (the
/// analogue of check-in's "Not Marcus?"), while the gutter's "Start over"
/// leaves the signup entirely.
class KioskMatchStep extends StatelessWidget {
  const KioskMatchStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.matchCandidate != cur.matchCandidate ||
          prev.matchSearchOpen != cur.matchSearchOpen ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final match = state.matchCandidate;
        final searching = state.matchSearchOpen || match == null;
        final busy = state.submitting;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.match,
          title: searching
              ? 'Find them by name'
              : 'Is this the same ${match.firstName}?',
          subtitle: searching
              ? 'Pick the person you\'re adding. We\'ll use their account '
                  'instead of making a second one.'
              : 'We already train a ${match.fullName}. If it\'s them, we\'ll '
                  'use their account instead of making a second one.',
          foot: KioskFlowFoot(
            // The decision lives in the panel, so the footer's middle column
            // carries only the way BACK and the other route in — a primary
            // here would compete with the two buttons that answer the actual
            // question.
            onPrimary: null,
            onBack: busy ? null : cubit.back,
            onSkip: searching || busy ? null : cubit.openMatchSearch,
            skipLabel: 'Search by name instead',
          ),
          child: KioskSignupFormPanel(
            children: searching
                ? const [KioskMatchSearch()]
                : [
                    KioskMatchCard(match: match, typed: state.pendingPayee),
                    _Decide(busy: busy),
                  ],
          ),
        );
      },
    );
  }
}

/// The two answers, centred under the card they are about.
class _Decide extends StatelessWidget {
  final bool busy;

  const _Decide({required this.busy});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    // A Wrap, not a Row: at kiosk button scale the two answers are wider than
    // the panel's measure, and neither may fall off the edge of the decision.
    return IntrinsicWrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        KioskOutlineButton(
          text: 'No — different person',
          onPressed: busy ? null : () => cubit.rejectMatch(),
        ),
        KioskPrimaryButton(
          text: 'Yes, that\'s them',
          onPressed: busy ? null : cubit.confirmMatch,
        ),
      ],
    );
  }
}
