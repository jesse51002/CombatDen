import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/sections_bar.dart';

/// Wraps a screen's content with the persistent `SectionsBar` on the left.
///
/// Every top-level screen returns `AppShell(activeRoute: ..., child: ...)`
/// so the nav rail and surrounding chrome stay identical across screens.
/// Pass `activeRoute` (one of the `AppRoutes.*` constants) so the matching
/// nav item highlights.
class AppShell extends StatelessWidget {
  final Widget child;
  final String? activeRoute;
  final Color? backgroundColor;

  const AppShell({
    super.key,
    required this.child,
    this.activeRoute,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? DesignConstants.backgroundColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionsBar(activeRoute: activeRoute),
          Expanded(child: child),
        ],
      ),
    );
  }
}
