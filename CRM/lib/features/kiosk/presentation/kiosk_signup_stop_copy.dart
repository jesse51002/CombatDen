import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';

/// The signup stop screen's member-facing words — the ONE place a
/// [KioskSignupStopReason] becomes a sentence, mirroring `kiosk_blocked_copy`.
///
/// Every line is **blame-free and stops at the fact**: the screen itself
/// supplies the front-desk handoff and the "nothing has been charged"
/// reassurance, so no line here may carry an error code, jargon, or any hint
/// the member did something wrong.
///
/// **The duplicate line never names or confirms the matched account.** The
/// 409 body carries the matches; rendering them would confirm to whoever is
/// standing at a shared iPad that a given person banks here, and it would be
/// useless anyway — the answer is the same either way.
String kioskSignupStopReasonCopy(KioskSignupStopReason? reason) {
  return switch (reason) {
    KioskSignupStopReason.duplicateMember =>
      'You already have an account here.',
    KioskSignupStopReason.trialAlreadyUsed =>
      'Trials are one to a member, and yours is used.',
    KioskSignupStopReason.alreadyOnPlan =>
      'You\'re already on that membership.',
    KioskSignupStopReason.paymentsUnavailable =>
      'This kiosk can\'t take payments right now.',
    KioskSignupStopReason.noPlansOffered =>
      'Memberships here are set up at the front desk.',
    KioskSignupStopReason.plansUnavailable =>
      'We couldn\'t load the memberships just now.',
    KioskSignupStopReason.previewFailed =>
      'We couldn\'t work out your total just now.',
    KioskSignupStopReason.paymentFailed =>
      'Something went wrong on our side.',
    KioskSignupStopReason.paymentUnconfirmed =>
      'We can\'t confirm whether that payment went through.',
    KioskSignupStopReason.cardDeclined => 'Your bank declined the payment.',
    KioskSignupStopReason.signupFailed || null =>
      'We couldn\'t finish setting you up just now.',
  };
}

/// The reassurance under the why-box. It differs by reason on exactly one
/// axis — what the desk can DO about it — because "the coach can pull up your
/// account" is a promise the gym can only keep for a duplicate.
///
/// **The money reasons say what happened to the money, first.** That is the
/// only question a member has after tapping Pay, and a stop screen that makes
/// them wonder is worse than no screen at all. The one case the kiosk cannot
/// answer ([KioskSignupStopReason.paymentUnconfirmed]) says so plainly rather
/// than guessing — and it never offers a retry, because retrying is the one
/// action that could take the money twice.
String kioskSignupStopReassurance(KioskSignupStopReason? reason) {
  return switch (reason) {
    KioskSignupStopReason.duplicateMember =>
      'Nothing\'s wrong, and nothing has been charged. The coach at the desk '
          'can pull up your account and add what you need in a minute.',
    KioskSignupStopReason.trialAlreadyUsed =>
      'Nothing\'s wrong, and nothing has been charged. The coach at the desk '
          'can talk you through the memberships and get you training.',
    KioskSignupStopReason.alreadyOnPlan =>
      'Nothing\'s wrong, and nothing has been charged. The coach at the desk '
          'can change your plan or add another one.',
    KioskSignupStopReason.noPlansOffered =>
      'Nothing\'s wrong, and nothing has been charged. The coach at the desk '
          'will get you going — it only takes a minute.',
    KioskSignupStopReason.paymentFailed =>
      'Nothing has been charged. Everything you filled in is saved, and the '
          'coach at the desk can finish this off for you.',
    KioskSignupStopReason.paymentUnconfirmed =>
      'We won\'t try that payment again in case it already went through. '
          'Please see the coach at the desk — they can check and finish this '
          'off for you.',
    KioskSignupStopReason.cardDeclined =>
      'You haven\'t been charged, and everything else you filled in is saved. '
          'The coach at the desk can take it from here.',
    KioskSignupStopReason.plansUnavailable ||
    KioskSignupStopReason.previewFailed ||
    KioskSignupStopReason.paymentsUnavailable ||
    KioskSignupStopReason.signupFailed ||
    null =>
      'Nothing\'s wrong, and nothing has been charged. The coach at the desk '
          'can get you signed up from there.',
  };
}
