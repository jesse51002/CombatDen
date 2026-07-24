import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/kiosk_payer_refusal_copy.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_waiver_status.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_who_for.dart';

/// "Change who is paying" — pick the member who pays for this signup.
///
/// **The people already on this roster come FIRST.** They are standing right
/// there, and making somebody search the whole gym for the person beside them
/// is the wrong shape — so the roster is listed and directly pickable, with
/// the CRM search underneath for anyone not on it yet. Both lists render
/// through the same `KioskNameRow`, because they are two sources of one kind
/// of answer rather than two kinds of control.
///
/// **The current payer is not offered.** Picking whoever is already paying is
/// a no-op dressed as a choice; they are named in the pinned strip instead, so
/// the screen still says who it is changing FROM.
///
/// **Every pick runs the same no-attached-card gate** — roster or CRM, created
/// in this signup or not. A refusal is INLINE (pick someone else, or carry on
/// paying yourself), never a terminal stop, because nothing on this screen has
/// committed anything.
class KioskPayerPickStep extends StatelessWidget {
  const KioskPayerPickStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.payerRefusal != cur.payerRefusal ||
          prev.persons != cur.persons ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final refusal = state.payerRefusal;
        final candidates = state.payerCandidateIndexes;
        final payer = state.payer;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.payerPick,
          title: 'Who\'s paying?',
          subtitle: 'Pick anyone here, or find another member. They enter '
              'their card at the end, and everyone on the list is on it.',
          // Who it is changing FROM, pinned so the answer does not scroll.
          identity: KioskWhoFor(
            eyebrow: 'PAYING NOW',
            name: '${payer.firstName} ${payer.lastName}'.trim(),
          ),
          foot: KioskFlowFoot(
            // The decision is a row in a list, so the footer carries only the
            // way back.
            onPrimary: null,
            onBack: state.submitting ? null : cubit.back,
          ),
          child: KioskSignupFormPanel(
            children: [
              if (refusal != null)
                KioskWaiverNotice(message: kioskPayerRefusalCopy(refusal)),
              if (candidates.isNotEmpty) ...[
                const KioskSectionHead(
                  title: 'Already here',
                  subtitle: 'Someone on this signup pays for everyone.',
                ),
                _RosterOptions(state: state, candidates: candidates),
              ],
              const KioskSectionHead(
                title: 'Someone else who trains here',
                subtitle: 'Find them by name.',
              ),
              const KioskMatchSearch(forPayer: true),
            ],
          ),
        );
      },
    );
  }
}

/// The roster, minus whoever is already paying.
///
/// The second line is each person's own masked email — the same treatment the
/// CRM results and the match card wear, so a shared iPad never prints an
/// address in full anywhere on this flow.
class _RosterOptions extends StatelessWidget {
  final KioskSignupState state;
  final List<int> candidates;

  const _RosterOptions({required this.state, required this.candidates});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < candidates.length; i++)
          KioskNameRow(
            name: '${state.persons[candidates[i]].firstName} '
                    '${state.persons[candidates[i]].lastName}'
                .trim(),
            note: kioskMaskedEmail(state.persons[candidates[i]].email),
            first: i == 0,
            onTap: () => cubit.pickPayerFromRoster(candidates[i]),
          ),
      ],
    );
  }
}
