/// `MembershipWizardState`, read into the shared components' view models.
///
/// The desk's half of the seam the kiosk's `kiosk_flow_views.dart` owns on the
/// other side. Every per-surface reading of what may be PRINTED happens here
/// rather than inside a widget both surfaces render — and the desk's readings
/// are the mirror of the lobby's: the address is handed over in FULL
/// (`IdentityPolicy.full`, the gym's own records on the gym's own screen), and
/// every roster row is editable, because staff correcting a typo is the whole
/// reason the row carries an Edit at all.
library;

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/payments_invoice_preview.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/membership_flow/domain/name_labels.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_money_view.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';

/// What ONE picked membership costs right now: the plan's list price for the
/// line, and what it comes to after the discounts attached to it.
///
/// Both figures, always — a discount nobody can see is a discount the member
/// never hears about, and the review states the pair on every reduced row.
/// The arithmetic is the shared `domain/discount_math.dart`, reached through
/// the capability; nothing here re-derives a price.
typedef WizardLineMoney = ({int grossMinorUnits, int netMinorUnits});

/// The line money for [draft], or null when its plan carries no active price
/// (which the catalogue filter already excludes from sale).
WizardLineMoney? wizardLineMoney(
  MembershipWizardState state,
  MembershipWizardDraft draft,
) {
  final unit = draft.plan.activePrice?.price;
  if (unit == null) return null;
  return (
    grossMinorUnits: unit * draft.quantity,
    netMinorUnits: state.discounts.lineTotalCents(
      unitPriceCents: unit,
      units: draft.quantity,
      presetIds: draft.presetIds,
      customs: draft.customs,
    ),
  );
}

/// [money] formatted, with the struck figure dropped where nothing came off —
/// a struck price equal to the real one is noise that teaches staff to ignore
/// the ones that mean something.
({String amount, String? struck}) wizardLineLabels(
  WizardLineMoney money, {
  String currency = 'usd',
}) {
  final net = formatMinorUnits(money.netMinorUnits, currency: currency);
  if (money.netMinorUnits >= money.grossMinorUnits) {
    return (amount: net, struck: null);
  }
  return (
    amount: net,
    struck: formatMinorUnits(money.grossMinorUnits, currency: currency),
  );
}

/// One roster row's person.
///
/// Everybody but the payer is removable — the payer is the one row the run
/// cannot lose — and removal here only takes somebody out of the RUN; no
/// member is deleted, and the semantic label says so.
///
/// Nobody is EDITABLE, which is the one place this surface offers less than
/// the kiosk's roster does. The desk has no in-flow dialog that edits a member
/// (the two adders CREATE and LINK), and the only thing an Edit could do from
/// here is leave for the member's own page — which would abandon a run staff
/// are halfway through assembling. A control that costs more than it fixes is
/// worse than no control, so the row does not draw one.
FlowPersonView wizardRosterPerson(
  MembershipWizardState state,
  MembershipWizardPerson person,
) =>
    FlowPersonView(
      firstName: person.firstName,
      fullName: person.name,
      identityLine: state.config.identity.identityLine(person.email),
      role: _role(person),
      training: person.training,
      editable: false,
      removable: !person.isPayer,
    );

/// The whole roster, payer first.
List<FlowPersonView> wizardRosterPeople(MembershipWizardState state) => [
      for (final person in state.people) wizardRosterPerson(state, person),
    ];

FlowPersonRole _role(MembershipWizardPerson person) =>
    person.isPayer ? FlowPersonRole.paying : FlowPersonRole.member;

/// The review's money readout for the request as it stands right now.
///
/// Every figure is lifted off the server preview in minor units; only the
/// LABELS are derived, and only ever from the roster.
FlowMoneyView wizardMoneyView(MembershipWizardState state) {
  final recurring = state.preview?.recurring;
  final card = state.savedCard;
  final lines = <PreviewInvoiceLine>[
    ...?state.preview?.oneTime?.lines,
    ...?state.effectiveDueNowInvoice?.lines,
  ];
  return FlowMoneyView(
    dueTodayMinorUnits: state.dueTodayMinor,
    currency: state.currency,
    lines: [
      for (final line in lines)
        FlowMoneyLine(
          label: _lineLabel(state, line) ?? line.description ?? '',
          amountMinorUnits: line.amount,
        ),
    ],
    prorated: state.prorated,
    prorationUntil: state.prorationEnds,
    chargedTwiceToday: state.chargedTwice,
    cardBrand: card?.brand,
    cardLast4: card?.lastFour,
    recurring: recurring == null
        ? null
        : FlowRecurringView(
            totalMinorUnits: recurring.total,
            cycleWord: wizardCycleWord(state),
            nextPaymentAt: recurring.nextPaymentAt,
            names: _recurringNames(state),
          ),
  );
}

/// "Ella · Unlimited Monthly" for one preview line, or null when the line
/// cannot be attributed to anyone this request carries.
///
/// Attribution is by `stripe_price_id`, never by arithmetic: this only puts a
/// name on the line's own amount. Two people on one plan consolidate into ONE
/// Stripe line, so both are named rather than a split being invented — the
/// desk never divides money either.
String? _lineLabel(MembershipWizardState state, PreviewInvoiceLine line) {
  final priceId = line.stripePriceId;
  if (priceId == null) return null;
  final names = <String>[];
  String? planName;
  for (final person in state.trainingPeople) {
    for (final draft in state.draftsFor(person.memberId)) {
      if (draft.plan.activePrice?.stripePriceId != priceId) continue;
      if (state.alreadyStarted(person.memberId, draft.plan.planId)) continue;
      final first = person.firstName.trim();
      if (first.isNotEmpty && !names.contains(first)) names.add(first);
      planName ??= draft.plan.planName;
    }
  }
  if (names.isEmpty || planName == null) return null;
  return '$planName · ${flowNameList(names)}';
}

/// The first names of everyone this request carries whose plan bills again —
/// what "then $X each cycle" is about. A one-off pack does not recur for the
/// child who got it, and implying it does is the small lie that produces a
/// phone call.
List<String> _recurringNames(MembershipWizardState state) {
  final names = <String>[];
  for (final person in state.trainingPeople) {
    final first = person.firstName.trim();
    if (first.isEmpty || names.contains(first)) continue;
    for (final draft in state.draftsFor(person.memberId)) {
      if (draft.plan.planType != PlanType.recurring) continue;
      if (state.alreadyStarted(person.memberId, draft.plan.planId)) continue;
      names.add(first);
      break;
    }
  }
  return names;
}

/// The recurring cart's own billing unit as a word, so "each month" is never
/// asserted about a weekly or yearly plan.
///
/// It falls back to the neutral "cycle" rather than a month: this sits over a
/// REAL charge, and a cadence it does not know is not one it may invent.
String wizardCycleWord(MembershipWizardState state) {
  final plan = _recurringPlan(state);
  final unit = plan?.durationUnit?.displayLabel.toLowerCase();
  if (plan == null || unit == null || unit == 'unknown') return 'cycle';
  final amount = plan.durationAmount ?? 1;
  return amount == 1 ? unit : '$amount ${unit}s';
}

MembershipPlanResponse? _recurringPlan(MembershipWizardState state) {
  for (final person in state.trainingPeople) {
    for (final draft in state.draftsFor(person.memberId)) {
      if (draft.plan.planType == PlanType.recurring) return draft.plan;
    }
  }
  return null;
}
