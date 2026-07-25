import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_buttons.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_card_chip.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_inline_notice.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_result_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_results_foot.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_signup_step_scaffold.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_two_charges_note.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// D7a — the per-person receipt for a landed start: who got what, whether it
/// started, and what the statement will show.
///
/// **It is the LEDGER, not the celebration.** The welcome screen keeps the green
/// disc and the app push; this screen is factual, and its marks are per-row
/// squares rather than a second confirmation disc — two celebrations for one
/// event teaches neither.
///
/// It draws TWO branches off the same panel:
///
/// * **every membership created** — the receipt, one `Next` into the welcome
///   screen. The flow count is already released by then (see
///   `KioskSignupCubit._enterResults`);
/// * **a PARTIAL** — some started, some did not, so money HAS moved for the
///   group that cleared and the decline popup's "you haven't been charged"
///   would be a false statement about it. This is the branch the screen exists
///   for. It carries the decline popup's own three actions, in its order, wired
///   to its cubit methods, plus the card chip: which card was used is the fact a
///   member wants before retrying.
///
/// An ALL-failed start never reaches here — it stays on `KioskDeclinedScreen`,
/// where "nothing was charged" is true and where the founder's retry ladder
/// lives, untouched.
///
/// The whole screen is bounded by the 60-second return countdown its foot draws:
/// a shared community iPad may not sit on any screen forever.
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
        return KioskSignupStepScaffold(
          step: KioskSignupStep.results,
          title: allCreated
              ? 'You\'re all set'
              : 'Some of these didn\'t go through',
          subtitle: _subtitle(state, allCreated: allCreated),
          // No identity strip: the scaffold's is "for the steps that are ABOUT
          // one person", and this screen is about the signup as a whole.
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
                    // The decline popup's ladder, at a narrower scope. "Retry
                    // the rest" rather than a bare "Retry": rows above it
                    // visibly succeeded, and "retry WHAT — all of it?" is the
                    // precise fear the notice answers.
                    KioskPrimaryButton(
                      text: 'Retry the rest',
                      onPressed: cubit.retrySameCard,
                    ),
                    KioskOutlineButton(
                      text: 'Try another card',
                      onPressed: cubit.retryCard,
                    ),
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

  /// The title branches on the OUTCOME; the subtitle branches on group-ness —
  /// the same split `KioskReviewStep` already uses.
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
        // On a partial, the one thing a member needs before they decide: the
        // rows that say Started are PAID, and a retry does not touch them.
        if (!allCreated)
          const KioskInlineNotice(
            message: 'The ones marked Started are paid for. Trying again only '
                'charges for the ones that didn\'t go through.',
          ),
        _ResultsPanel(state: state, allCreated: allCreated),
        // Which card was used — the fact a member wants in hand before
        // retrying, exactly as the decline popup shows it. On the all-created
        // branch it is noise: the money already moved.
        if (!allCreated)
          Center(
            child: KioskCardChip(
              brand: state.cardBrand,
              last4: state.cardLast4,
            ),
          ),
      ],
    );
  }
}

/// One panel, not the review's two-up: a receipt is one list. The review
/// panels' shell verbatim, with the hairline between rows the group review
/// already uses between person blocks.
class _ResultsPanel extends StatelessWidget {
  final KioskSignupState state;
  final bool allCreated;

  const _ResultsPanel({required this.state, required this.allCreated});

  @override
  Widget build(BuildContext context) {
    final rows = kioskResultRowsInRosterOrder(state);
    final receipt = state.payerOrNull?.email.trim() ?? '';
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
            style: DesignConstants.kioskEyebrow,
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Hairline(),
            KioskResultRow(label: rows[i].label, status: rows[i].item.status),
          ],
          // Both halves of the statement actually carry money AND every row
          // landed — on a partial one of the two charges did not happen, so
          // "two separate charges" would be false.
          if (allCreated && state.chargedTwiceToday)
            const KioskTwoChargesNote(),
          // Unreachable blank: an email is required at the details step. If one
          // is ever missing the line is dropped rather than printed empty.
          if (receipt.isNotEmpty)
            Text(
              'Your receipt is on its way to $receipt.',
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
/// `<Person> · <Plan>`.
///
/// The receipt reads in the same order as the group review the member just
/// approved, which is not the response's order. An item whose member is not on
/// the roster is unreachable — `_startItems` builds from the roster — but is
/// appended last if it ever happens, and its label degrades to the PLAN name
/// alone: a wrong name on a member-facing screen is worse than none.
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
