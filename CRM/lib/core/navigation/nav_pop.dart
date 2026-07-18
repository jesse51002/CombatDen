import 'package:flutter/material.dart';

/// Safe back-navigation for **page-level** routes on the authenticated
/// app's nested [Navigator] (see `auth_gate.dart::_MembersWorkspace`).
///
/// That navigator boots from the URL hash with exactly one route after a
/// hard reload (deliberate — no synthetic back stack is rebuilt). A page
/// reached that way — a hard reload on a deep link, or a typed/bookmarked
/// hash — is the ONLY entry on the stack, so a bare `Navigator.pop()`
/// empties it and renders a blank white screen. [popOrGoTo] pops when
/// there is somewhere to pop back to (normal in-app back nav) and falls
/// back to a deterministic replacement route otherwise, so the screen
/// always lands somewhere real.
///
/// Every page-level "back"/"cancel"/post-save pop should go through this
/// helper with the screen's natural parent route as [fallbackRoute] (see
/// `CRM/CLAUDE.md`'s Routing section). Dialog and bottom-sheet pops are
/// exempt — they pop the overlay, not a page, and always have a page
/// beneath them to return to.

/// Pops the current route if the Navigator can (normal in-app back nav);
/// otherwise deterministically replaces it with [fallbackRoute] — so a
/// screen reached as the sole stack entry (hard reload on a deep URL, or
/// a typed/bookmarked hash) never pops into a blank Navigator.
void popOrGoTo(BuildContext context, String fallbackRoute, {Object? result}) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
  } else {
    navigator.pushReplacementNamed(fallbackRoute);
  }
}
