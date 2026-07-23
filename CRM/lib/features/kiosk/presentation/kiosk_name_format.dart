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
