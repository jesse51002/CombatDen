/// What a LANDED start says, split three ways.
///
/// A decline arrives as a RESULT in a 2xx body (a 207 is a 2xx), never as an
/// HTTP error, so the split is read off the items. The three are genuinely
/// different outcomes and must never collapse into "worked / didn't": on a
/// PARTIAL money HAS moved for the group that cleared, so a screen claiming
/// "nothing was charged" there would be a lie about a real charge.
enum MembershipWizardOutcome {
  /// Every membership in the request was created.
  allCreated,

  /// Some created, some not. A retry re-sends only the un-created ones.
  partial,

  /// Every membership was refused — the only outcome where "nothing was
  /// charged" is true.
  allFailed,
}

/// A commit that produced no per-item breakdown at all, and why.
///
/// Distinct from a `failed` RESULT item: these are the cases where the request
/// either never went out or came back with nothing to itemise, so the surface
/// must say something other than "your memberships failed".
enum MembershipWizardCommitError {
  /// The idempotency key on this attempt has ALREADY been posted and its
  /// outcome is unknown. Re-posting it is the one action that could take a
  /// member's money twice, so the attempt hard-stops here and the desk
  /// confirms in Stripe. This is the `_sentAttempts` latch firing.
  unconfirmed,

  /// A 409 — the backend recognised the key and replayed an earlier identical
  /// start. The ORIGINAL start stands, charge included; nothing was charged
  /// twice.
  alreadyStarted,

  /// There was nothing to send: an unassemblable request, or a retry whose
  /// scope had emptied. Nothing left the device.
  nothingToSend,

  /// The call itself failed before any per-item outcome came back.
  failed,
}
