/// Formats a member's full name for the shared kiosk screen as first name plus
/// last initial — "Marcus Brown" -> "Marcus B.". A supervised, shared iPad
/// shouldn't show a full member name that bystanders can read off the screen,
/// so this is the single, centralized transform every kiosk surface reuses
/// whenever it renders a name (name search now; Phase C2/D reuse it).
///
/// A pure display transform — it never mutates the model. Only the last
/// initial is capitalized; the first name is passed through untouched (the
/// backend supplies proper casing). Edge cases: a single-token name renders
/// as-is ("Cher" -> "Cher"); surrounding or repeated whitespace collapses; an
/// empty (or whitespace-only) name yields an empty string.
String kioskDisplayName(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  final lastInitial = parts.last.substring(0, 1).toUpperCase();
  return '${parts.first} $lastInitial.';
}
