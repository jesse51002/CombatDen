import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';

/// The SOLO signup's step labels — the 6-step template the rail renders while
/// the roster holds only the payer.
///
/// The labels live HERE, not in the shared rail: they are this surface's spine,
/// and the desk's wizard brings its own to the same widget.
const List<String> kKioskSoloSteps = [
  'You',
  'Details',
  'Plan',
  'Waiver',
  'Card',
  'Pay',
];

/// The GROUP template (founder ruling 8): a second person on the roster makes
/// "People" a step of its own and re-labels the rail to seven.
///
/// The people step is ALWAYS visited, even solo ("It's just me" → Plans), so
/// what a second person changes is the LABELLING, never whether the rail
/// renders — mind that when mapping a step onto its rung index.
const List<String> kKioskGroupSteps = [
  'You',
  'Details',
  'People',
  'Plans',
  'Waivers',
  'Card',
  'Pay',
];

/// Which rung of the shared rail a [KioskSignupStep] lights.
///
/// The mapping is the KIOSK's, because the spine it maps is: the desk's wizard
/// walks its own steps and brings its own mapping to the same rail.
///
/// The two templates differ by ONE rung (ruling 8): the solo rail has no
/// "People" of its own, so its roster steps light the rung the member is
/// heading INTO rather than one already finished — a rail must never sit on a
/// completed step.
///
/// The templates are fixed at 6 solo / 7 group (`kKioskSoloSteps` /
/// `kKioskGroupSteps`) and no step adds a rung: a step still about WHO this
/// person is (the entry fork, the identify search, the payer match) shares the
/// rung they are standing on rather than advertising progress they have not
/// made.
int kioskRailIndex(KioskSignupStep step, {required bool isGroup}) {
  return switch (step) {
    KioskSignupStep.entry ||
    KioskSignupStep.identify ||
    KioskSignupStep.details =>
      0,
    KioskSignupStep.extraDetails || KioskSignupStep.payerMatch => 1,
    KioskSignupStep.people ||
    KioskSignupStep.personDetails ||
    KioskSignupStep.match ||
    KioskSignupStep.payerPick =>
      2,
    KioskSignupStep.plans => isGroup ? 3 : 2,
    KioskSignupStep.waivers => isGroup ? 4 : 3,
    KioskSignupStep.card => isGroup ? 5 : 4,
    // Review / Paying / Results / Declined / Welcome are ONE act from the
    // member's side, so they share the final "Pay" rung: the rail must not
    // imply a step exists between reviewing and paying.
    KioskSignupStep.review ||
    KioskSignupStep.paying ||
    KioskSignupStep.results ||
    KioskSignupStep.declined ||
    KioskSignupStep.welcome =>
      isGroup ? 6 : 5,
    // The stop screen draws no rail (a terminal is not a step), so this value
    // is never used; it stays in range rather than throwing.
    KioskSignupStep.stop => 0,
  };
}
