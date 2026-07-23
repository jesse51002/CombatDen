import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/route_guard.dart';
import 'package:crm/core/navigation/url_sync.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/gym_setup/data/models/gym_with_role.dart';
import 'package:crm/features/gym_setup/data/repositories/gym_repository.dart';
import 'package:crm/features/gym_setup/presentation/screens/gym_setup_screen.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_state.dart';
import 'package:crm/features/kiosk/presentation/kiosk_locked_screen.dart';
import 'package:crm/features/kiosk/presentation/kiosk_screen.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/presentation/screens/gym_picker_screen.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/loading_screen.dart';

/// Top-level auth gate that decides the whole app subtree
/// from [LoginBloc] state:
///
/// - `LoginInitial` / `LoginLoading` → a [LoadingScreen]
///   while the initial auth check runs.
/// - `LoginUnauthenticated` / `LoginError` → the
///   [LoginScreen].
/// - `LoginAuthenticated` → list the gyms the caller may
///   administer with `GET /api/v1/gyms/`; **0** → the
///   [GymSetupScreen]; **1** → mount the members workspace
///   scoped to that gym (in a nested [Navigator] so the
///   section nav keeps working); **2+** → the
///   [GymPickerScreen], then the workspace once a gym is
///   chosen.
///
/// The nested authenticated [Navigator] shares the admin
/// route table ([routeBuilders] passed from `main.dart`)
/// so a section tap (`pushReplacementNamed`) resolves the
/// same screens — and the whole subtree is torn down on
/// sign-out, returning to [LoginScreen] cleanly.
class AuthGate extends StatelessWidget {
  /// The admin route table from `main.dart`, reused by the
  /// authenticated nested navigator. Kept here as a param so
  /// the route map stays a single source of truth.
  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  const AuthGate({super.key, required this.onGenerateRoute});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginBloc, LoginState>(
      builder: (context, state) {
        return switch (state) {
          // Only the initial boot auth-check shows a full-screen
          // loader. LoginLoading is emitted by sign-in/sign-up
          // submits, which must keep the LoginScreen mounted (so
          // it shows its own button spinner + inline error) — it
          // falls through to the LoginScreen case below.
          LoginInitial() => const LoadingScreen(),
          LoginAuthenticated() => _AuthenticatedGate(
              onGenerateRoute: onGenerateRoute,
            ),
          _ => const LoginScreen(),
        };
      },
    );
  }
}

/// Lists the gyms the caller may administer once authenticated,
/// then mounts the setup wizard (0), the members workspace (1),
/// or the gym picker (2+). Stateful so the `GET /api/v1/gyms/`
/// fetch fires exactly once per authenticated session, not on
/// every rebuild.
class _AuthenticatedGate extends StatefulWidget {
  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  const _AuthenticatedGate({required this.onGenerateRoute});

  @override
  State<_AuthenticatedGate> createState() =>
      _AuthenticatedGateState();
}

class _AuthenticatedGateState
    extends State<_AuthenticatedGate> {
  late final GymRepository _gymRepository;
  late Future<List<GymWithRole>> _gymsFuture;

  @override
  void initState() {
    super.initState();
    _gymRepository = GymRepository(apiClient: ApiClient());
    _gymsFuture = _resolveGyms();
  }

  @override
  void dispose() {
    // Sign-out tears down this gate (any path — the nav-rail Logout, the
    // Supabase session-expiry listener, or the 401 escape hatch all emit
    // LoginUnauthenticated). Clear the gym selection here, the symmetric
    // counterpart to _activate, so the next session re-resolves gyms instead
    // of reusing the stale gym (the build skips the picker while gymId != null).
    selectedGym.reset();
    // Drop the signed-out employee's theme so a shared machine's login screen
    // doesn't keep the prior user's appearance; the next sign-in re-hydrates
    // from that employee's gym_employees row in [_activate].
    themeController.setMode(ThemeMode.system);
    super.dispose();
  }

  /// Hard ceiling on the gym fetch so the full-screen auth spinner can
  /// never hang indefinitely. Kept longer than the 401 interceptor's
  /// refresh timeout so an expired session resolves to login (via the
  /// sign-out escape hatch) before this fires; this only catches a
  /// genuinely stuck call, surfacing the [_GymCheckError] retry instead.
  static const Duration _gymFetchTimeout = Duration(seconds: 30);

  /// List the gyms the caller administers. When there's exactly one,
  /// activate it immediately so we land straight in the workspace;
  /// otherwise the build routes to the picker (2+) or the setup
  /// wizard (0).
  Future<List<GymWithRole>> _resolveGyms() async {
    final gyms =
        await _gymRepository.getMyGyms().timeout(_gymFetchTimeout);
    if (gyms.length == 1) {
      _activate(gyms.first);
    }
    return gyms;
  }

  /// Make [gym] the active admin gym (its real UUID scopes every CRM
  /// member query) and seed the read-only content surfaces.
  ///
  /// The **content** gym is a default VideoService `template_gym`
  /// ([AppConstants.defaultVideoGymId]) recorded as [selectedGym]'s
  /// `videoGymId` — NOT the real `gym.gymId`. The real gym id (a UUID)
  /// and the VideoService `template_gym` id (a string like `boxing`) are
  /// separate id spaces with no mapping, so passing the real UUID 404s
  /// the VideoService and breaks every content surface. The real gym's
  /// name shows in the admin chrome via `gymName` (the public theme
  /// browser's preview name instead comes from
  /// `ThemeRuntime.activeDesignName`). The gym's saved
  /// ThemeService design ([GymWithRole.themeDesignId]) is passed through
  /// so the Theme tab can boot on it; the theme itself isn't applied here
  /// (the theme runtime isn't initialized yet — the Theme tab does it).
  /// The gym's uploaded [GymWithRole.logoUrl] (nullable) seeds the nav
  /// chrome and the Gym profile editor.
  void _activate(GymWithRole gym) {
    // Hydrate the saved CRM appearance for this gym before the workspace paints
    // (the app root rebuilds MaterialApp off [themeController]).
    themeController.hydrate(gym.themePreference);
    selectedGym.setActiveGym(
      gymId: gym.gymId,
      displayName: gym.gymName,
      role: gym.role,
      timezone: gym.timezone,
      logoUrl: gym.logoUrl,
      savedThemeDesignId: gym.themeDesignId,
      createdAt: gym.createdAt,
    );
    // Seed the content gym (drives the read-only member-app content surfaces);
    // in the admin context this also fetches the real gym's showcase.
    selectedGym.setVideoGymId(videoGymId: AppConstants.defaultVideoGymId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GymWithRole>>(
      future: _gymsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return _GymCheckError(
            onRetry: () => setState(() {
              _gymsFuture = _resolveGyms();
            }),
          );
        }
        final gyms = snapshot.data ?? const <GymWithRole>[];
        if (gyms.isEmpty) {
          return const GymSetupScreen();
        }
        // One gym was auto-activated in _resolveGyms; a picked gym
        // sets it via onSelected. Either way, an active gym → mount
        // the workspace — UNLESS Kiosk Mode is engaged, in which case
        // the member self-serve surface intercepts it. The kiosk branch
        // lives INSIDE the authenticated branch on purpose: a persisted
        // kiosk flag is only ever honored while a session exists, so a
        // flag without a session is inert (it fails closed to the login
        // screen above). The admin session + selectedGym stay live
        // underneath; leaving kiosk is what signs out.
        if (selectedGym.gymId != null) {
          return BlocBuilder<KioskSessionCubit, KioskSessionState>(
            builder: (context, kiosk) {
              // Until the persisted kiosk flag has been read, show a neutral
              // loader — NEVER _MembersWorkspace. This closes the boot/reload
              // window where the old `inactive` initial state mounted the admin
              // workspace (whose nested navigator boots at the URL fragment and
              // fires its backend fetch) before `_restore` could swap in the
              // kiosk. A member on a kiosk iPad can no longer point the address
              // bar at an admin route and have it render on a reload.
              if (kiosk.isRestoring) return const LoadingScreen();
              if (kiosk.isEnded) return const KioskLockedScreen();
              if (kiosk.isKioskVisible) return const KioskScreen();
              return _MembersWorkspace(
                onGenerateRoute: widget.onGenerateRoute,
              );
            },
          );
        }
        return GymPickerScreen(
          gyms: gyms,
          onSelected: (gym) => setState(() => _activate(gym)),
        );
      },
    );
  }
}

/// The authenticated app: a nested [Navigator] rooted at the
/// members route, using the shared admin route table. Each
/// screen wraps itself in `AppShell`, so the section nav
/// rail renders without the gate having to.
class _MembersWorkspace extends StatelessWidget {
  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  const _MembersWorkspace({required this.onGenerateRoute});

  @override
  Widget build(BuildContext context) {
    // Deep-link support: boot at the route in the URL fragment
    // (e.g. `/#/schedule`) so any admin page is directly reachable
    // on a fresh load — but only when the active role may open it.
    // With no fragment (or a forbidden one) start on the role's
    // landing route instead. `redirectRouteFor` returns the landing
    // route for a forbidden path and null for an allowed one, so this
    // both picks the default landing screen and rejects a forbidden
    // deep link in one step. The custom onGenerateInitialRoutes builds
    // a single route (no synthetic back stack from path splitting).
    final role = selectedGym.role;
    final fragment = Uri.base.fragment;
    final requested = (fragment.isNotEmpty && fragment != '/')
        ? fragment
        : (role?.landingRoute ?? AppRoutes.home);
    final initial = redirectRouteFor(requested, role) ?? requested;
    return Navigator(
      initialRoute: initial,
      onGenerateRoute: onGenerateRoute,
      // Reflect section navigation into the browser address bar — only the root
      // navigator does this automatically, and all section nav runs here.
      observers: [UrlSyncObserver()],
      onGenerateInitialRoutes: (navigator, initialRoute) => [
        onGenerateRoute(RouteSettings(name: initialRoute)),
      ],
    );
  }
}

class _GymCheckError extends StatelessWidget {
  final VoidCallback onRetry;

  const _GymCheckError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(
            DesignConstants.paddingBig,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingLarge,
            children: [
              Text(
                'We couldn\'t load your gym.',
                style: DesignConstants.h2,
                textAlign: TextAlign.center,
              ),
              AppPrimaryButton(
                text: 'Try again',
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
