import 'package:flutter/widgets.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/gym/theme_hydration.dart';
import 'package:mobile_app/features/member_select/data/models/member_identity.dart';

/// Switch the app to [member]: record the selection, hydrate that gym's
/// branding, and reset to a fresh home.
///
/// The ONE in-app switch path — both the "Switch profile" screen and the
/// topbar identity sheet call it, so the two can never drift on which fields
/// get recorded (`gymAddress` in particular feeds class-detail "Open in Maps")
/// or on where a switch lands.
///
/// Takes the [navigator] rather than a `BuildContext` because both callers
/// can be torn down mid-switch: `AppShell` re-keys on the new member id, so the
/// caller's element is often gone by the time hydration resolves. The
/// `NavigatorState` is captured BEFORE the first await and re-checked after.
Future<void> applyMemberSelection({
  required NavigatorState navigator,
  required MemberIdentity member,
}) async {
  await selectedMember.select(
    memberId: member.memberId,
    gymId: member.gymId,
    gymName: member.gymName,
    firstName: member.firstName,
    lastName: member.lastName,
    gymAddress: member.gymAddress,
    gymLogoUrl: member.gymLogoUrl,
    photoUrl: member.photoUrl,
  );
  // Never throws — a null/unresolvable design leaves the current theme.
  await GymThemeHydration().applyForGym(member.gymId);
  // If the theme (or the member id) changed, the AppShell re-keyed this
  // navigator away and it is already rooted at a fresh home. Otherwise reset
  // to home ourselves so a switch always lands on a fresh app.
  if (!navigator.mounted) return;
  navigator.pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
}
