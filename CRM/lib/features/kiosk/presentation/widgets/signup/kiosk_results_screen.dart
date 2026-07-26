import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_results_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_step_scaffold.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_card_chip.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_result_row.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_two_charges_note.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// D7a — the per-person receipt for a landed start: who got what, whether it
/// started, and what the statement will show.
///
/// **The three-way start-response split lands here twice.** All-created and
/// PARTIAL both draw this receipt; only an ALL-failed start goes to
/// `KioskDeclinedScreen`, where "you haven't been charged" is true. On a
/// partial money HAS moved for the rows that cleared, so this screen keeps
/// Retry live — the decline popup's ladder at a narrower scope — plus (founder
/// ruling) the same `Next` the all-created branch shows, demoted to the outline
/// tier so a partial has a working way forward and not only a way back.
///
/// It is the LEDGER, not the celebration: the welcome screen keeps the green
/// disc and the app push. The 60-second return countdown in its foot bounds the
/// screen — a shared iPad may not sit anywhere forever.
class KioskResultsScreen extends StatelessWidget {
  const KioskResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KioskSignupCubit>();
    return BlocBuilder<KioskSignupCubit, KioskSignupState>(
      buildWhen: (prev, cur) =>
          prev.startResult != cur.startResult ||
          prev.popupCountdown != cur.popupCountdown ||
          prev.persons != cur.persons ||
          prev.cardBrand != cur.cardBrand ||
          prev.cardLast4 != cur.cardLast4,
      builder: (context, state) {
        final allCreated = state.allCreated;
        return KioskStepScaffold(
          step: KioskSignupStep.results,
          title: allCreated
              ? 'You\'re all set'
              : 'Some of these didn\'t go through',
          subtitle: _subtitle(state, allCreated: allCreated),
          // No identity strip: that band is for steps about ONE person, and
          // this screen is about the signup as a whole.
          foot: KioskResultsFoot(
            secondsLeft: state.popupCountdown,
            actions: allCreated
                ? [
                    KioskPrimaryButton(
                      text: 'Next',
                      onPressed: cubit.nextFromResults,
                    ),
                  ]
                : [
                    // "Retry the rest", not a bare "Retry": the rows above it
                    // visibly succeeded and must not read as re-charged.
                    KioskPrimaryButton(
                      text: 'Retry the rest',
                      onPressed: cubit.retrySameCard,
                    ),
                    KioskOutlineButton(
                      text: 'Try another card',
                      onPressed: cubit.retryCard,
                    ),
                    // A partial has a working way ON, not only a way back
                    // (founder ruling): otherwise a member who did not want to
                    // retry was held until the countdown abandoned the flow,
                    // and the rows that DID start never reached the app push.
                    KioskOutlineButton(
                      text: 'Next',
                      onPressed: cubit.nextFromResults,
                    ),
                    // The desk handoff stays at the bottom wherever it appears:
                    // always available, never a destination the kiosk picks.
                    KioskOutlineButton(
                      text: 'Get help at the desk',
                      onPressed: cubit.getHelpAtDesk,
                    ),
                  ],
          ),
          child: _Body(state: state, allCreated: allCreated),
        );
      },
    );
  }

  /// The title branches on the OUTCOME; the subtitle branches on group-ness.
  String _subtitle(KioskSignupState state, {required bool allCreated}) {
    if (!allCreated) {
      return 'Have a look — you can try the rest on the same card.';
    }
    return state.isGroup
        ? 'Every membership below started today.'
        : 'Your membership started today.';
  }
}

class _Body extends StatelessWidget {
  final KioskSignupState state;
  final bool allCreated;

  const _Body({required this.state, required this.allCreated});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        // The two things a member needs before deciding: the rows marked
        // Started are PAID and a retry does not touch them, and not retrying is
        // a real option — the front desk finishes the rest. Without that second
        // sentence `Next` is illegible beside "Retry the rest".
        if (!allCreated)
          const FlowInlineNotice(
            message: 'The ones marked Started are paid for. Trying again only '
                'charges for the ones that didn\'t go through. Or tap Next and '
                'ask the front desk to finish the rest.',
          ),
        _ResultsPanel(state: state, allCreated: allCreated),
        // Which card was used — the fact a member wants in hand before
        // retrying. On the all-created branch it is noise.
        if (!allCreated)
          Center(
            child: FlowCardChip(
              brand: state.cardBrand,
              last4: state.cardLast4,
            ),
          ),
      ],
    );
  }
}

/// One panel, not the review's two-up: a receipt is one list. The review
/// panels' shell verbatim, hairlines and all.
class _ResultsPanel extends StatelessWidget {
  final KioskSignupState state;
  final bool allCreated;

  const _ResultsPanel({required this.state, required this.allCreated});

  @override
  Widget build(BuildContext context) {
    final rows = kioskResultRowsInRosterOrder(state);
    final contact = state.payerOrNull?.email.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text(
            state.isGroup ? 'MEMBERSHIPS' : 'YOUR MEMBERSHIP',
            style: DesignConstants.eyebrow,
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Hairline(),
            FlowResultRow(label: rows[i].label, status: rows[i].item.status),
          ],
          // All-created only: on a partial one of the two charges did not
          // happen, so "two separate charges" would be false.
          if (allCreated && state.chargedTwiceToday)
            const FlowTwoChargesNote(),
          // NOT a receipt line — nothing emails a receipt. There is no mailer,
          // and the connected account notifies on a FAILED payment only, so
          // promising one here would be a falsehood told at the moment money
          // changed hands. It states the address a failure notice would reach,
          // which is what earns showing it unmasked on a shared iPad. A blank
          // address drops the line rather than printing it empty.
          if (contact.isNotEmpty)
            Text(
              'If a payment ever fails, we\'ll email you at $contact.',
              style: DesignConstants.kioskCaption.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
        ],
      ),
    );
  }
}

/// One result item paired with the words that label it.
class KioskResultRowData {
  final MemberMembershipsStartResultItem item;
  final String label;

  const KioskResultRowData({required this.item, required this.label});
}

/// The landed items in the ROSTER's order (payer first), each labelled
/// `<Person> · <Plan>` — the order the member just approved on the review,
/// which is not the response's order.
///
/// An item whose member is not on the roster is unreachable, but is appended
/// last if it ever happens, labelled by PLAN alone: a wrong name on a
/// member-facing screen is worse than none.
List<KioskResultRowData> kioskResultRowsInRosterOrder(KioskSignupState state) {
  final items = state.startItems;
  final taken = <int>{};
  final rows = <KioskResultRowData>[];
  for (final person in state.persons) {
    final id = person.memberId;
    if (id == null) continue;
    for (var i = 0; i < items.length; i++) {
      if (taken.contains(i) || items[i].memberId != id) continue;
      taken.add(i);
      rows.add(
        KioskResultRowData(
          item: items[i],
          label: _label(
            person: '${person.firstName} ${person.lastName}'.trim(),
            plan: state.planById(items[i].planId)?.planName,
          ),
        ),
      );
    }
  }
  for (var i = 0; i < items.length; i++) {
    if (taken.contains(i)) continue;
    rows.add(
      KioskResultRowData(
        item: items[i],
        label: _label(
          person: '',
          plan: state.planById(items[i].planId)?.planName,
        ),
      ),
    );
  }
  return rows;
}

/// `<Person> · <Plan>`, degrading to whichever half is known. A plan the warmed
/// catalogue no longer carries falls back to the generic word rather than an id.
String _label({required String person, required String? plan}) {
  final planName = (plan == null || plan.trim().isEmpty) ? null : plan.trim();
  if (person.isEmpty) return planName ?? 'Membership';
  if (planName == null) return person;
  return '$person · $planName';
}
