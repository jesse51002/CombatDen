import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_section_head.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_match_search.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_name_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_foot.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_form_panel.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';

/// "Who's paying?" — pick the member who pays for this signup.
///
/// Two situations through one screen. Changing payer: the current one is named
/// in the pinned `PAYING NOW` strip and is NOT offered as a row (picking
/// whoever already pays is a no-op dressed as a choice). Choosing one after the
/// previous payer was DELETED: no strip, everyone selectable, and the flow
/// cannot continue until one is chosen (see the People step's block).
///
/// The roster comes first — those people are standing right there — with the
/// CRM search under it for anyone not on it yet. Both lists render through the
/// same affordant [KioskNameRow] so a pickable member reads as pressable. An
/// existing member with a card on file is a fine payer here (the fresh-card
/// law; see `kiosk_card_step.dart`).
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
        return KioskStepScaffold(
          step: KioskSignupStep.payerPick,
          title: 'Who\'s paying?',
          subtitle: payer == null
              ? 'Pick who pays for everyone here. They enter their card at '
                  'the end, and everyone on the list is on it.'
              : 'Pick anyone here, or find another member. They enter their '
                  'card at the end, and everyone on the list is on it.',
          // Who it is changing FROM, pinned so the answer does not scroll.
          identity: payer == null
              ? null
              : FlowWhoFor(
                  eyebrow: 'PAYING NOW',
                  name: '${payer.firstName} ${payer.lastName}'.trim(),
                ),
          foot: FlowFoot(
            // The decision is a row in the list, so the foot has no primary.
            onPrimary: null,
            onBack: state.submitting ? null : cubit.back,
            onEscape: cubit.abandon,
          ),
          child: FlowFormPanel(
            children: [
              // A CRM hit already on the roster is a REDIRECT, not a rejection:
              // nothing on this screen has committed anything.
              if (state.payerAlreadyInSignup)
                const FlowInlineNotice(
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
/// The second line is each person's MASKED email: a shared iPad never prints an
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
