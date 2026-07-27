/// `KioskSignupState`, read into the shared money panel's view model.
///
/// Every figure is lifted straight off the preview response, in minor units —
/// a price is never derived from a plan row here. Only the LABELS are derived,
/// and only ever from the roster.
library;

import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/membership_flow/domain/name_labels.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_money_view.dart';

/// The review's money readout for the request as it stands right now.
FlowMoneyView kioskMoneyView(KioskSignupState state) {
  final recurring = state.preview?.recurring;
  final lines = <PreviewInvoiceLine>[
    ...?state.preview?.oneTime?.lines,
    ...?state.preview?.dueNow?.lines,
  ];
  return FlowMoneyView(
    dueTodayMinorUnits: state.dueTodayMinorUnits,
    currency: state.currency,
    lines: [
      for (final line in lines)
        FlowMoneyLine(
          label: _lineLabel(state, line) ?? line.description ?? 'Membership',
          amountMinorUnits: line.amount,
        ),
    ],
    prorated: state.chargedProrated,
    prorationUntil: state.prorationUntil,
    chargedTwiceToday: state.chargedTwiceToday,
    cardBrand: state.cardBrand,
    cardLast4: state.cardLast4,
    recurring: recurring == null
        ? null
        : FlowRecurringView(
            totalMinorUnits: recurring.total,
            cycleWord: _cycleWord(state),
            nextPaymentAt: recurring.nextPaymentAt,
            // Solo has nobody to disambiguate from, so the line stays about
            // "you" rather than naming the one person on screen.
            names: state.isGroup ? _recurringNames(state) : const <String>[],
          ),
  );
}

/// "Ella · Kids Program" for one preview line, or null when the line cannot be
/// attributed to anyone on this roster.
///
/// Attribution is by `stripe_price_id`, never by arithmetic: this only puts a
/// name on the line's own amount. A shared price (two children on one plan
/// consolidate into ONE line) names both rather than inventing a split — the
/// kiosk never divides money.
///
/// Only people the priced request actually carries are named
/// ([KioskSignupState.isBeingCharged]), so a retry after a partial failure —
/// which re-prices only the memberships that did not start — cannot put
/// already-paid-for people on a line they are not on.
String? _lineLabel(KioskSignupState state, PreviewInvoiceLine line) {
  final priceId = line.stripePriceId;
  if (priceId == null) return null;
  final names = <String>[];
  String? planName;
  for (final person in state.persons) {
    if (!state.isBeingCharged(person)) continue;
    final plan = state.planById(person.selectedPlanId);
    if (plan == null || plan.activePrice?.stripePriceId != priceId) continue;
    final first = person.firstName.trim();
    if (first.isNotEmpty) names.add(first);
    planName ??= plan.planName;
  }
  if (names.isEmpty || planName == null) return null;
  return '${flowNameList(names)} · $planName';
}

/// The first names of everyone the priced request carries whose plan bills
/// again — what the review's "Then $X each month" line is about. A one-off
/// pack does not recur for its owner, and implying it does is the small lie
/// that produces a phone call. Same [KioskSignupState.isBeingCharged] scope
/// [_lineLabel] uses, so a retry names only the people it is for.
List<String> _recurringNames(KioskSignupState state) => [
      for (final person in state.persons)
        if (state.isBeingCharged(person) &&
            state.planById(person.selectedPlanId)?.planType ==
                PlanType.recurring &&
            person.firstName.trim().isNotEmpty)
          person.firstName.trim(),
    ];

/// The recurring plan's own billing unit, so "each month" is never asserted
/// about a weekly or yearly plan. It reads the FIRST recurring plan in the
/// cart, not the active person's — at the review nobody is active, and a
/// non-training payer has no plan at all.
///
/// It falls back to the neutral "cycle" rather than `planCycleLabel`'s
/// "month": that label sits under a plan whose cycle is known, while this one
/// sits over a real charge and may not invent one.
String _cycleWord(KioskSignupState state) {
  final plan = _recurringPlan(state);
  if (plan == null) return 'cycle';
  final unit = plan.durationUnit?.displayLabel.toLowerCase();
  final amount = plan.durationAmount ?? 1;
  if (unit == null || unit == 'unknown') return 'cycle';
  return amount == 1 ? unit : '$amount ${unit}s';
}

MembershipPlanResponse? _recurringPlan(KioskSignupState state) {
  for (final person in state.persons) {
    if (!person.training) continue;
    final plan = state.planById(person.selectedPlanId);
    if (plan?.planType == PlanType.recurring) return plan;
  }
  return null;
}
