import 'package:flutter/material.dart';
import 'package:theme_flutter/customization_runtime.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/offline_banner.dart';

/// The authenticated app: a nested [Navigator] over the shared app route
/// table, rooted at the home route. Re-keyed on the active design id so a live
/// theme switch (a member switch, or the initial hydration) rebuilds the whole
/// app tree from a fresh Home — needed because the app's widgets read the
/// `DesignConstants` static getters (not `Theme.of`), so already-pushed routes
/// wouldn't otherwise re-theme.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.onGenerateRoute});

  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: ValueKey(ThemeRuntime.activeDesignId),
      onGenerateRoute: onGenerateRoute,
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        onGenerateRoute(RouteSettings(name: initialRoute)),
      ],
    );
  }
}

/// The app booted read-degraded from the cached selection (the identity fetch
/// was offline). The dismissible [OfflineBanner] sits above the app; the app
/// content drops its own top inset while the banner is up so the two don't
/// double-inset.
class OfflineApp extends StatelessWidget {
  const OfflineApp({
    super.key,
    required this.onGenerateRoute,
    required this.bannerDismissed,
    required this.onRetry,
    required this.onDismiss,
  });

  final Route<dynamic> Function(RouteSettings) onGenerateRoute;
  final bool bannerDismissed;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.backgroundColor,
      child: Column(
        children: [
          if (!bannerDismissed)
            SafeArea(
              bottom: false,
              child: OfflineBanner(onRetry: onRetry, onDismiss: onDismiss),
            ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: !bannerDismissed,
              child: AppShell(onGenerateRoute: onGenerateRoute),
            ),
          ),
        ],
      ),
    );
  }
}
