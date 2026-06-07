import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/shared/widgets/navigation/app_top_bar.dart';
import 'package:crm/shared/widgets/navigation/sections_bar.dart';

/// Wraps a screen's content with the app's persistent navigation chrome.
///
/// Every top-level screen returns `AppShell(activeRoute: ..., child: ...)` so
/// the nav stays identical across screens. Pass `activeRoute` (one of the
/// `AppRoutes.*` constants) so the matching nav item highlights.
///
/// Responsive: at desktop widths the nav is the left [SectionsBar] rail beside
/// the content; below [DesignConstants.navMobileBreakpoint] it collapses to an
/// [AppTopBar] (logo + section title + hamburger) above the content, whose
/// hamburger drops the full-width section dropdown.
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
    // The app reads DesignConstants statically (never `Theme.of`), so when the
    // theme mode flips, an ancestor repaint alone won't re-theme the visible
    // page — it sits in the nested navigator's preserved route and only rebuilds
    // on navigation. Listen to [themeController] here (the chrome every
    // authenticated screen wraps in) and re-key the page content on the resolved
    // brightness so it re-inflates and picks up the new palette immediately. The
    // screen's bloc/repository sit ABOVE AppShell, so they survive untouched
    // (no re-fetch); only the visible page's transient UI (e.g. scroll) resets.
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final page = KeyedSubtree(
          key: ValueKey<bool>(themeController.isDark),
          child: child,
        );
        return Scaffold(
          backgroundColor: backgroundColor ?? DesignConstants.backgroundColor,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile =
                  constraints.maxWidth < DesignConstants.navMobileBreakpoint;
              if (isMobile) {
                return Column(
                  children: [
                    AppTopBar(activeRoute: activeRoute),
                    Expanded(child: page),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionsBar(activeRoute: activeRoute),
                  Expanded(child: page),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
