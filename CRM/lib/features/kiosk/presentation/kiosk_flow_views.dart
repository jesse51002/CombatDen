/// `KioskSignupState`, read into the shared components' view models.
///
/// This is the SEAM: the shared roster row and review panels take plain data,
/// so every kiosk-only reading of what may be printed happens here rather than
/// inside a widget the desk also renders. The two that matter:
///
/// - the address is MASKED on every identity line, because a lobby iPad has a
///   queue reading over the member's shoulder (the desk hands staff the full
///   one);
/// - only a person whose record this signup CREATED is editable — the kiosk
///   prints no stored detail of an existing member on a shared screen.
library;

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_name_format.dart';
import 'package:crm/features/membership_flow/domain/plan_labels.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_person_view.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_plan_summary.dart';
import 'package:crm/features/membership_flow/presentation/models/flow_signed_waiver_view.dart';

/// The plan [person] picked, or null when they picked none.
///
/// The price is the plan's own LIST price — "what you picked", not "what you
/// pay". The authoritative charge is the preview's, on the money panel.
FlowPlanSummary? kioskPlanSummary(
  KioskSignupState state,
  KioskSignupPerson person,
) {
  final plan = state.planById(person.selectedPlanId);
  if (plan == null) return null;
  final price = plan.activePrice?.price;
  return FlowPlanSummary(
    name: plan.planName,
    rule: planAllowanceLabel(plan),
    imageUrl: plan.imageUrl,
    amountLabel:
        price == null ? null : formatMinorUnits(price, currency: 'USD'),
  );
}

/// One roster row's person, with the affordances that row may offer.
FlowPersonView kioskRosterPerson(KioskSignupState state, int index) {
  final person = state.persons[index];
  return FlowPersonView(
    firstName: person.firstName,
    fullName: _fullName(person),
    // Null before their details step has run — hence "Added just now".
    identityLine: kioskMaskedEmail(person.email),
    role: _role(person),
    training: person.training,
    editable: !person.wasExisting,
    removable: state.canRemovePerson(index),
  );
}

/// One review block's person, carrying the membership they picked and whether
/// an earlier attempt already started it.
FlowPersonView kioskReviewPerson(
  KioskSignupState state,
  KioskSignupPerson person,
) {
  return FlowPersonView(
    firstName: person.firstName,
    fullName: _fullName(person),
    identityLine: kioskMaskedEmail(person.email),
    role: _role(person),
    plan: kioskPlanSummary(state, person),
    started: state.alreadyStarted(person),
  );
}

/// The whole roster for the GROUP review, in roster order (payer first).
List<FlowPersonView> kioskReviewPeople(KioskSignupState state) => [
      for (final person in state.persons) kioskReviewPerson(state, person),
    ];

/// What has been signed during this signup, in signing order.
List<FlowSignedWaiverView> kioskSignedWaivers(KioskSignupState state) => [
      for (final signed in state.signedWaivers)
        FlowSignedWaiverView(
          name: signed.name,
          signerName: signed.signerName,
        ),
    ];

String _fullName(KioskSignupPerson person) =>
    '${person.firstName} ${person.lastName}'.trim();

/// The payer's role wins over everything else — it is the fact that explains
/// the whole screen (one card covers everybody here).
FlowPersonRole _role(KioskSignupPerson person) {
  if (person.isPayer) return FlowPersonRole.paying;
  return person.wasExisting ? FlowPersonRole.member : FlowPersonRole.newcomer;
}
