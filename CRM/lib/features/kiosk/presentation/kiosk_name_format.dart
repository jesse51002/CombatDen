/// The member's FIRST name only — for the direct-address kiosk greetings ("Hi
/// Marcus, pick your class" / "Nice one, Marcus."). Falls back to [fallback]
/// (default "there") when the name is empty/whitespace. The centralized
/// transform every kiosk greeting reuses; passes the first token through
/// untouched (the backend supplies proper casing).
String kioskFirstName(String? fullName, {String fallback = 'there'}) {
  final trimmed = fullName?.trim() ?? '';
  if (trimmed.isEmpty) return fallback;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// An email with its local part masked after the first character —
/// `e•••••@gmail.com`.
///
/// **The kiosk never prints another member's stored email in full.** The match
/// card has to say enough for a parent to recognise their own child's address
/// and no more: whoever is standing at a shared lobby iPad must not be able to
/// read a stranger's contact details off it. Returns null when there is
/// nothing to mask, so a caller renders no line at all rather than an empty
/// one.
String? kioskMaskedEmail(String? email) {
  final trimmed = email?.trim() ?? '';
  final at = trimmed.indexOf('@');
  if (at < 1) return trimmed.isEmpty ? null : trimmed;
  return '${trimmed[0]}•••••${trimmed.substring(at)}';
}
