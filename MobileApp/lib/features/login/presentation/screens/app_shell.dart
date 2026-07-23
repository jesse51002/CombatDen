import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theme_flutter/customization_runtime.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/login/presentation/widgets/app_lifecycle_refresh.dart';
import 'package:mobile_app/features/login/presentation/widgets/gate/offline_banner.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_event.dart';
import 'package:mobile_app/features/profile/data/repositories/member_profile_repository.dart';

/// The authenticated app: a nested [Navigator] over the shared app route
/// table, rooted at the home route, with the app-wide [MemberProfileBloc]
/// provided ABOVE it so the topbar and later features read one profile source.
///
/// Its whole subtree is re-keyed on the active design id AND the selected
/// member id, so switching profiles — even to another member at the SAME gym
/// (no theme change) — re-inflates the tree: a fresh [MemberProfileBloc] loads
/// the new member and the navigator resets to a fresh Home, resetting every
/// feature bloc. The re-key on design id also re-themes already-pushed routes
/// (the app reads the `DesignConstants` static getters, not `Theme.of`).
///
/// The shell navigator carries a stable [GlobalKey] (owned by the state, so it
/// survives ambient rebuilds) so the app-open celebration check in
/// [AppLifecycleRefresh] — which sits ABOVE the navigator — can push the
/// post-class flow onto it.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.onGenerateRoute});

  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // Rebuild on a same-gym member switch (no theme change), so the keyed
    // subtree below re-inflates and resets every bloc.
    return ListenableBuilder(
      listenable: selectedMember,
      builder: (context, _) {
        return KeyedSubtree(
          key: ValueKey(
            '${ThemeRuntime.activeDesignId}::${selectedMember.memberId}',
          ),
          child: BlocProvider<MemberProfileBloc>(
            create: (_) => MemberProfileBloc(
              repository: MemberProfileRepository(apiClient: ApiClient()),
            )..add(const MemberProfileLoadRequested()),
            child: AppLifecycleRefresh(
              navigatorKey: _navigatorKey,
              child: Navigator(
                key: _navigatorKey,
                onGenerateRoute: widget.onGenerateRoute,
                onGenerateInitialRoutes: (navigator, initialRoute) => [
                  widget.onGenerateRoute(RouteSettings(name: initialRoute)),
                ],
              ),
            ),
          ),
        );
      },
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
