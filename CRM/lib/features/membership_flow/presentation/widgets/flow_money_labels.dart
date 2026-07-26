import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// "Ella and Theo" — a natural list of first names, so a money line reads like
/// a sentence a parent would say rather than a comma-separated dump.
String flowNameList(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
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
String? flowLineLabel(KioskSignupState state, PreviewInvoiceLine line) {
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
/// [flowLineLabel] uses, so a retry names only the people it is for.
List<String> flowRecurringNames(KioskSignupState state) => [
      for (final person in state.persons)
        if (state.isBeingCharged(person) &&
            state.planById(person.selectedPlanId)?.planType ==
                PlanType.recurring &&
            person.firstName.trim().isNotEmpty)
          person.firstName.trim(),
    ];
