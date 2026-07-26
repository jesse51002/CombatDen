/// Every word the two in-run "add a person" dialogs say.
///
/// They are one task pointed two ways — the roster adds a PAYEE the payer pays
/// for, the payer switch adds a PAYER for the launch member — and both end in
/// the same authorized-payer signature. So the wording lives here once and
/// takes the [AuthorizeDirection], rather than twice with a `not` between them:
/// the old wizard put both directions on adjacent screens in identical copy,
/// and staff picked the wrong one.
///
/// The voice is `StaffFlowCopy`'s — third person, addressed to somebody
/// selling on a member's behalf, and every line states its CONSEQUENCE rather
/// than its mechanism.
library;

import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';

abstract final class StartPersonCopy {
  // ── Chrome ────────────────────────────────────────────────────────────────

  static const String closeSemantic = 'Close without adding anyone';
  static const String cancel = 'Cancel';
  static const String back = 'Back';
  static const String close = 'Close';

  // ── Create (the new-member dialog) ────────────────────────────────────────

  static String createWhat(AuthorizeDirection direction) =>
      direction == AuthorizeDirection.addPayee
          ? 'Add someone new'
          : 'Add a new payer';

  static String createSubtitle({
    required AuthorizeDirection direction,
    required String gymName,
    required String anchorName,
  }) {
    final gym = gymName.trim().isEmpty ? 'This gym' : gymName.trim();
    return direction == AuthorizeDirection.addPayee
        ? '$gym creates the profile, then authorizes $anchorName to pay '
            'for them.'
        : '$gym creates the profile, then authorizes them to pay for '
            '$anchorName.';
  }

  /// Which fields are the price of getting past this screen, said once at the
  /// top because the shared form marks none of them.
  static const String createFieldsNote =
      'First name, last name and email are the only required fields — the '
      'phone, address, emergency contact and photo below are all optional. '
      'Everyone needs their own email; it\'s how they sign in. The photo is '
      'uploaded to this gym\'s library, and there is no default to fall back '
      'on.';

  static const String createPrimary = 'Add member';

  // ── Duplicate ─────────────────────────────────────────────────────────────

  static const String duplicateTitle = 'This may already be a member';

  static String duplicateSubtitle(int matches) => matches == 1
      ? 'One profile looks like the one being created.'
      : '$matches profiles look like the one being created.';

  /// What each of the three ways out actually costs. The footer names the
  /// verbs; nothing else on the screen says what they DO.
  static const String duplicateConsequences =
      'Going back keeps every value already typed. Creating a second profile '
      'splits their attendance, ranks and billing across two records. Using '
      'the existing member reuses the profile that is already there — and '
      'where the authorization already exists, the signing step is skipped.';

  // ── Find an existing member (the link dialog) ─────────────────────────────

  static const String findWhat = 'Find an existing member';
  static const String findTitle = 'Find an existing member';

  static String findSubtitle({
    required AuthorizeDirection direction,
    required String anchorName,
  }) =>
      direction == AuthorizeDirection.addPayee
          ? '$anchorName will be authorized to pay for whoever is picked.'
          : 'Whoever is picked will be authorized to pay for $anchorName.';

  static const String findPaging = 'Loading more as you scroll · 20 at a time';

  /// Said on the list itself, so nobody hunts for a name that can never
  /// appear there.
  static String findNotListed({
    required AuthorizeDirection direction,
    required String anchorName,
  }) =>
      direction == AuthorizeDirection.addPayee
          ? 'People $anchorName is already authorized to pay for aren\'t '
              'listed here.'
          : 'People already authorized to pay for $anchorName aren\'t listed '
              'here.';

  static const String findPrimary = 'Continue';

  // ── Authorize the payer ───────────────────────────────────────────────────

  static const String signDocTitle = 'Authorized payer agreement';

  static String signTitle(String payerName, String payeeName) =>
      'Authorize $payerName to pay for $payeeName';

  static const String signSubtitle =
      'One member can\'t be billed for another without a signature. Once '
      'signed, this pair never signs again.';

  static const String signEyebrow = 'SIGNING AS';

  static String signBannerNote(String payeeName) =>
      'The payer signs this one — it is their money being committed to '
      '$payeeName\'s bill.';

  static const String signConsentLabel =
      'This agreement has been read and agreed to. Typing the name counts as '
      'a signature.';

  static const String signConsentNote =
      'The name appears in the document above as it is typed.';

  /// What signing DOES, stated before the signature rather than only
  /// confirmed after it.
  static String signOutcome(String payerName, String payeeName) =>
      'On signing, $payerName is authorized to pay for $payeeName. Nothing is '
      'charged by this step.';

  static const String signPrimary = 'Sign and authorize';

  static String signSuccess(String payerName, String payeeName) =>
      '$payerName is now authorized to pay for $payeeName.';

  static const String waiverLoadFailed =
      'We couldn\'t load the waiver. Please try again.';

  static const String unexpectedError = 'An unexpected error occurred.';

  static const String fallbackPayer = 'The payer';
  static const String fallbackPayee = 'this member';
}
