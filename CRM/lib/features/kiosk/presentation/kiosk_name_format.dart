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
String? kioskMaskedEmail(String? email) {
  final trimmed = email?.trim() ?? '';
  final at = trimmed.indexOf('@');
  if (at < 1) return trimmed.isEmpty ? null : trimmed;
  return '${trimmed[0]}•••••${trimmed.substring(at)}';
}
