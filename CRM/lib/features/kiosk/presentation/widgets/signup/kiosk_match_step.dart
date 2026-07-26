import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_step_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_card.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// E2 — "Is this the same Ella?" The PAYEE duplicate, offered back for
/// confirmation: a payee pays nothing, so reusing their existing account is
/// the right outcome rather than something to warn about. The payer's own
/// duplicate is answered on its own step (`payerMatch`), never here.
///
/// Two decisions sit on this screen at different scales: the panel's "No —
/// different person" corrects WHO this is (check-in's "Not Marcus?"), while
/// the gutter's "Start over" leaves the signup entirely.
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
        // Kiosk-only step: staff never meet a payee duplicate mid-wizard, so
        // this head lives on the kiosk's own copy.
        final copy = kioskStepCopy(context);
        return KioskStepScaffold(
          step: KioskSignupStep.match,
          title: copy.matchStepTitle(
            searching: searching,
            firstName: match?.firstName ?? '',
          ),
          subtitle: copy.matchStepSubtitle(
            searching: searching,
            fullName: match?.fullName ?? '',
          ),
          foot: FlowFoot(
            // The decision lives in the panel, so no primary here — it would
            // compete with the two buttons that answer the actual question.
            onPrimary: null,
            onBack: busy ? null : cubit.back,
            onSkip: searching || busy ? null : cubit.openMatchSearch,
            skipLabel: 'Search by name instead',
            onEscape: cubit.abandon,
          ),
          child: FlowFormPanel(
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
    // A Wrap, not a Row: at kiosk button scale the two answers out-measure the
    // panel, and neither may fall off the edge of the decision.
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
