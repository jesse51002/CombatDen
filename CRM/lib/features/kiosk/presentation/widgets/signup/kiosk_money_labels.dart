import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';

/// "Ella and Theo" — a natural list of first names, so a money line reads like
/// a sentence a parent would say rather than a comma-separated dump.
String kioskNameList(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}

/// "Ella · Kids Program" for one preview line, or null when the line cannot be
/// attributed to anyone on this roster.
///
/// **Attribution is by `stripe_price_id`, never by arithmetic.** The line's own
/// amount is the authoritative figure and it is rendered untouched; all this
/// does is put a name on it. Where a price is shared (two children on the same
/// plan consolidate into ONE subscription item, so ONE line) the row names
/// both of them rather than inventing a split — the kiosk never divides money.
///
/// **Only the people the priced request actually carries are named**
/// ([KioskSignupState.isBeingCharged], the same predicate the cart items are
/// built from). After a partial failure a retry re-prices ONLY the memberships
/// that did not start, so naming everyone who merely SHARES that price would
/// put people who are already paid for on a line they are not on.
String? kioskLineLabel(KioskSignupState state, PreviewInvoiceLine line) {
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
  return '${kioskNameList(names)} · $planName';
}

/// The first names of everyone the priced request carries whose plan bills
/// again — what the review's "Then $X each month" line is actually about. A
/// one-off pack does not recur for its owner, and saying otherwise about a
/// child's class pack is the kind of small lie that produces a phone call.
///
/// It reads the same [KioskSignupState.isBeingCharged] scope
/// [kioskLineLabel] does, so a review re-entered after a partial failure (via
/// "Try another card") names only the people that retry is for.
List<String> kioskRecurringNames(KioskSignupState state) => [
      for (final person in state.persons)
        if (state.isBeingCharged(person) &&
            state.planById(person.selectedPlanId)?.planType ==
                PlanType.recurring &&
            person.firstName.trim().isNotEmpty)
          person.firstName.trim(),
    ];
