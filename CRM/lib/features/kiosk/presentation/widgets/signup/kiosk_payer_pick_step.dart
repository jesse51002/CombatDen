import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_flow_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_inline_notice.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_form_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_who_for.dart';

/// "Who's paying?" — pick the member who pays for this signup.
///
/// It serves TWO situations through one screen:
///
/// * **Changing** who pays, while a payer already exists. The current payer is
///   named in the pinned `PAYING NOW` strip and is NOT offered as a row (picking
///   whoever already pays is a no-op dressed as a choice).
/// * **Choosing** a payer after the previous one was DELETED. There is no payer
///   yet, so the strip is gone and every remaining person is selectable — the
///   flow cannot continue until one is chosen (see the People step's block).
///
/// **The people already on this roster come FIRST.** They are standing right
/// there, so the roster is listed and directly pickable, with the CRM search
/// underneath for anyone not on it yet. Both lists render through the same
/// affordant [KioskNameRow] — bordered, ripple, chevron — so a pickable member
/// reads unmistakably as pressable, and the section heads are demoted to quiet
/// labels so the rows dominate.
///
/// **Whoever is picked types a fresh card at the end**, and it replaces
/// whatever is on their profile — so an existing member with a card on file is
/// a perfectly good payer here. The one thing this screen answers inline is a
/// CRM hit who is already on the roster: a redirect to the list above, never a
/// refusal, because nothing on this screen has committed anything.
class KioskPayerPickStep extends StatelessWidget {
  const KioskPayerPickStep({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.payerAlreadyInSignup != cur.payerAlreadyInSignup ||
          prev.persons != cur.persons ||
          prev.submitting != cur.submitting,
      builder: (context, state) {
        final candidates = state.payerCandidateIndexes;
        final payer = state.payerOrNull;
        return KioskSignupStepScaffold(
          step: KioskSignupStep.payerPick,
          title: 'Who\'s paying?',
          subtitle: payer == null
              ? 'Pick who pays for everyone here. They enter their card at '
                  'the end, and everyone on the list is on it.'
              : 'Pick anyone here, or find another member. They enter their '
                  'card at the end, and everyone on the list is on it.',
          // Who it is changing FROM, pinned so the answer does not scroll. With
          // no payer yet (the previous one was deleted) there is nothing to pin.
          identity: payer == null
              ? null
              : KioskWhoFor(
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
              // A REDIRECT, not a rejection — and the ONE line this screen
              // has to say, so it lives here rather than in a copy map of one.
              if (state.payerAlreadyInSignup)
                const KioskInlineNotice(
                  message: 'They\'re already on this signup — pick them from '
                      'the list above.',
                ),
              if (candidates.isNotEmpty) ...[
                const KioskSectionHead(
                  title: 'Already here',
                  subtitle: 'Someone on this signup pays for everyone.',
                  quiet: true,
                ),
                _RosterOptions(state: state, candidates: candidates),
              ],
              const KioskSectionHead(
                title: 'Someone else who trains here',
                subtitle: 'Find them by name.',
                quiet: true,
              ),
              const KioskMatchSearch(forPayer: true),
            ],
          ),
        );
      },
    );
  }
}

/// The roster candidates — everyone the picker offers, in roster order.
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final index in candidates)
          KioskNameRow(
            name: '${state.persons[index].firstName} '
                    '${state.persons[index].lastName}'
                .trim(),
            note: kioskMaskedEmail(state.persons[index].email),
            onTap: () => cubit.pickPayerFromRoster(index),
          ),
      ],
    );
  }
}
