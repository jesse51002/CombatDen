import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';

/// The payer picker's inline refusal — the ONE place a
/// [KioskPayerEligibility] becomes member-facing words, mirroring
/// `kiosk_signup_stop_copy.dart`.
///
/// **It is a refusal, not a dead end.** The member can pick somebody else or
/// carry on paying themselves, so every line names the fact and points at the
/// desk without ending anything. None of them says whether the person has a
/// membership, what they pay, or anything else about them.
///
/// The failed-check line says plainly that we could not confirm it, rather
/// than guessing: the kiosk refuses on an unanswered check exactly as it
/// refuses on a card already on file, and the words have to be honest about
/// which of the two happened.
String kioskPayerRefusalCopy(KioskPayerEligibility? refusal) {
  return switch (refusal) {
    KioskPayerEligibility.hasPaymentMethod =>
      'That member already has a card on file — the front desk can set this '
          'up for you.',
    // A REDIRECT, not a rejection: they are listed above and pickable there.
    KioskPayerEligibility.alreadyInSignup =>
      'They\'re already on this signup — pick them from the list above.',
    KioskPayerEligibility.unknown ||
    KioskPayerEligibility.eligible ||
    null =>
      'We couldn\'t confirm this — the front desk can set it up.',
  };
}
