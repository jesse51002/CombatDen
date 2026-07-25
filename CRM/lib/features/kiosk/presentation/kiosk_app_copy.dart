/// Every kiosk line that names the MEMBER APP, in one place — no call site
/// assembles them.
///
/// **The member app is white-labelled**: each gym's members download *their
/// gym's* app, so a member-facing kiosk line names the GYM, never "CombatDen"
/// (founder ruling — the platform's name means nothing to the person at the
/// iPad). The name comes from `selectedGym.gymName`, which can be null or
/// blank, so every builder degrades to the generic "the App" rather than
/// printing a sentence with a hole in it — and never substitutes a stand-in
/// name, since a wrong gym name is worse than none.
library;

/// The gym's name as it may be used inside copy, or null when the kiosk has
/// none worth printing (absent, or whitespace only).
String? kioskGymName(String? gymName) {
  final trimmed = gymName?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// The "Get the app" card's title — the modal's own title.
/// `Get the Iron Den App` / `Get the App` with no gym name.
String kioskGetAppTitle(String? gymName) {
  final name = kioskGymName(gymName);
  return name == null ? 'Get the App' : 'Get the $name App';
}

/// The home QR half's quiet adoption line.
String kioskAppStoreLine(String? gymName) {
  final name = kioskGymName(gymName);
  return name == null
      ? 'Get the app in the App Store.'
      : 'Get the $name app in the App Store.';
}

/// The glance rewards panel's funnel line when the gym HAS a reward catalogue.
String kioskRedeemInAppLine(String? gymName) {
  final name = kioskGymName(gymName);
  return name == null
      ? 'Redeem rewards in the app'
      : 'Redeem rewards in the $name app';
}

/// The glance rewards panel's funnel line when the gym has no rewards yet, so
/// the nudge points at booking instead of redeeming.
String kioskBookInAppLine(String? gymName) {
  final name = kioskGymName(gymName);
  return name == null
      ? 'Get the app to book classes'
      : 'Get the $name app to book classes';
}
