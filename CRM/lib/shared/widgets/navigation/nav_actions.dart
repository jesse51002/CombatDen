import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_flow.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/navigation/nav_sections.dart';

/// Shared navigation + sign-out behavior for the nav chrome. Both the desktop
/// rail and the mobile dropdown call into these so the routing and logout
/// logic lives in one place.

/// Navigate to a section root via `pushReplacementNamed` (so switching
/// sections doesn't pile up route history).
///
/// Skips only when we're truly already on that screen — compared to the
/// *actual* current route, not the highlighted [activeRoute], because a detail
/// sub-screen (e.g. member detail) highlights its parent section while living
/// on its own route, so tapping that section must still navigate back to the
/// section root instead of no-opping.
void goToSection(BuildContext context, String route) {
  final currentRoute = ModalRoute.of(context)?.settings.name;
  if (route == currentRoute) return;
  Navigator.of(context).pushReplacementNamed(route);
}

/// Tap handler for a [NavSection]: the primary CTA opens the add-member flow;
/// any other section navigates to its route.
void onNavSectionTap(BuildContext context, NavSection section) {
  if (section.isPrimary) {
    _openAddMemberFlow(context);
    return;
  }
  final route = section.route;
  if (route == null) {
    debugPrint('${section.label} is out of scope this pass');
    return;
  }
  goToSection(context, route);
}

/// Opens the add-member flow from the primary nav CTA. When it closes without
/// having navigated to a member itself, jump to the People section if anyone
/// was added (so the new member is visible); otherwise stay put.
Future<void> _openAddMemberFlow(BuildContext context) async {
  final outcome = await AddMemberFlow.show(context);
  if (!context.mounted) return;
  if (outcome.navigatedToMember) return;
  if (outcome.createdCount > 0) goToSection(context, AppRoutes.members);
}

/// Confirm, then sign out. Reads the [LoginBloc] *before* the await so the
/// dispatch never touches a `BuildContext` across the async gap. The auth gate
/// (a `BlocBuilder` on [LoginBloc]) swaps back to the login screen on the
/// resulting `LoginUnauthenticated`, and tearing that subtree down clears the
/// selected gym — so no navigation is needed here.
Future<void> confirmAndLogout(BuildContext context) async {
  final bloc = context.read<LoginBloc>();
  final confirmed = await ConfirmationModal.show(
    context: context,
    title: 'Log out?',
    message: 'You’ll need to sign in again to manage your gym.',
    confirmLabel: 'Log out',
  );
  if (!confirmed) return;
  bloc.add(const LoginSignOutRequested());
}
