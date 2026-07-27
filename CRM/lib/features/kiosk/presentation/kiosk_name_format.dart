import 'package:crm/features/membership_flow/config/identity_policy.dart';

/// The member's FIRST name only, for the direct-address kiosk greetings ("Hi
/// Marcus, pick your class"). Falls back to [fallback] when the name is
/// empty/whitespace, and passes the first token through untouched — the
/// backend supplies proper casing.
String kioskFirstName(String? fullName, {String fallback = 'there'}) {
  final trimmed = fullName?.trim() ?? '';
  if (trimmed.isEmpty) return fallback;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// An email with its local part masked after the first character —
/// `e•••••@gmail.com`.
///
/// **The kiosk never prints another member's stored email in full**: the match
/// card must say enough for a parent to recognise their own child's address
/// and no more, because anyone at a shared lobby iPad can read it. Returns
/// null when there is nothing to mask, so the caller renders no line at all.
///
/// The rule itself lives in [IdentityPolicy] — the membership flow's two
/// surfaces choose between this reading and the desk's full one, and one
/// implementation is what stops the masked form drifting from the policy that
/// is supposed to describe it. This name stays because the kiosk's call sites
/// read as a kiosk rule, which is what it is.
String? kioskMaskedEmail(String? email) =>
    const IdentityPolicy.masked().identityLine(email);
