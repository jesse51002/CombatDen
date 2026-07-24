/// Every kiosk line that names the MEMBER APP, in one place.
///
/// **The member app is white-labelled.** Each gym's members download *their
/// gym's* app, so a member-facing kiosk line names the GYM — never
/// "CombatDen", which is the platform's name and means nothing to the person
/// standing at the iPad. Founder ruling; it applies to the "Get the app" modal,
/// the home's spanning adoption line, and the glance's redeem/book nudges
/// alike.
///
/// The gym name comes from `selectedGym.gymName`, which is nullable (and can be
/// blank for a gym that never set one), so every builder here degrades to
/// naming the app generically — "Get the App" — rather than printing an empty
/// word or a sentence with a hole in it. It never substitutes a stand-in gym
/// name: on a member-facing screen a wrong gym name is worse than no gym name.
///
/// This is the ONE place these strings live; no kiosk call site assembles them.
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
