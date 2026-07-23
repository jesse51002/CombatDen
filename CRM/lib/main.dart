import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/config/environment.dart';
import 'package:crm/core/config/supabase_config.dart';
import 'package:crm/core/constants/env_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/route_guard.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/employees/presentation/screens/employee_detail_screen.dart';
import 'package:crm/features/growth/presentation/screens/growth_screen.dart';
import 'package:crm/features/home/presentation/screens/home_screen.dart';
import 'package:crm/features/kiosk/bloc/kiosk_session_cubit.dart';
import 'package:crm/features/kiosk/data/kiosk_server_clock.dart';
import 'package:crm/features/kiosk/data/kiosk_session_store.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/data/repositories/auth_repository.dart';
import 'package:crm/features/login/presentation/screens/auth_gate.dart';
import 'package:crm/features/members/presentation/screens/member_app_screen.dart';
import 'package:crm/features/members/presentation/screens/specific_member_screen.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/presentation/screens/edit_rank_screen.dart';
import 'package:crm/features/memberships/presentation/screens/membership_details_screen.dart';
import 'package:crm/features/memberships/presentation/screens/memberships_screen.dart';
import 'package:crm/features/memberships/presentation/screens/rank_detail_screen.dart';
import 'package:crm/features/memberships/presentation/screens/waiver_editor_screen.dart';
import 'package:crm/features/people/presentation/screens/people_screen.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:crm/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:crm/features/settings/presentation/screens/settings_screen.dart';
import 'package:crm/features/video_agent/presentation/screens/video_agent_screen.dart';
import 'package:crm/shared/themes/app_theme.dart';

Future<void> main() async {
  // Bring up the backend stack before the first frame.
  // Each step is best-effort: a failure is logged and the
  // app still boots (degraded), so a missing key or an
  // offline Supabase never leaves a blank screen — the auth
  // gate then shows the login screen instead.
  WidgetsFlutterBinding.ensureInitialized();

  // Seed the theme controller's platform brightness so `system` mode resolves
  // correctly on first paint; [AppManagementRoot] keeps it current thereafter.
  themeController.setPlatformBrightness(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  try {
    await SupabaseConfig.initialize();
  } catch (e, s) {
    log('Supabase init failed', error: e, stackTrace: s);
  }

  try {
    Stripe.publishableKey = EnvironmentConfig.get(
      EnvConstants.stripePublishable,
    );
    await Stripe.instance.applySettings();
  } catch (e, s) {
    log('Stripe init failed', error: e, stackTrace: s);
  }

  runApp(const AppManagementRoot());
}

class AppManagementRoot extends StatefulWidget {
  const AppManagementRoot({super.key});

  @override
  State<AppManagementRoot> createState() => _AppManagementRootState();
}

class _AppManagementRootState extends State<AppManagementRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Keep `system` theme mode tracking the OS as it flips light↔dark.
    themeController.setPlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the theme mode (or resolved brightness)
    // changes: every widget reads DesignConstants directly, so swapping
    // AppTheme.current + repainting re-skins the entire tree at once.
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        title: 'CombatDen Admin',
        theme: AppTheme.current,
        debugShowCheckedModeBanner: false,
        // Required by the flutter_quill waiver editor's toolbar.
        localizationsDelegates: const [
          FlutterQuillLocalizations.delegate,
        ],
        // Always mount the auth gate as the root, no matter the
        // deep-linked URL: auth + gym resolution must complete
        // before any page renders. The gate's nested navigator
        // reads the URL fragment to choose the actual page. Without
        // forcing this, a deep-link like `/#/members` routes here
        // directly and mounts the page before the gym is seeded
        // (empty gym_id → 422). `onGenerateRoute` is still used by
        // that nested navigator (and post-login section nav).
        onGenerateRoute: _onGenerateRoute,
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<dynamic>(
            builder: (_) =>
                _AuthGateHost(onGenerateRoute: _onGenerateRoute),
          ),
        ],
      ),
    );
  }
}

/// Provides [LoginBloc] and the app-root [KioskSessionCubit] above the
/// [AuthGate], and wires two escape hatches:
///
/// - The **401 escape hatch**: when the API client gives up on a request
///   (refresh failed), sign the session out so the gate drops to login.
/// - The **kiosk fate-share clear**: a [BlocListener] fires when the login
///   bloc reports the session gone ([LoginUnauthenticated]) and asks the
///   kiosk cubit to clear its persisted flag — but the cubit only actually
///   clears once it confirms the session is truly gone, so a failed sign-out
///   keeps the flag (fail-closed) rather than stranding the iPad in admin.
///
/// The kiosk cubit sits ABOVE the gate so entering kiosk swaps the whole
/// authenticated subtree (nested navigator, route table, `AppShell`) for the
/// member surface without disturbing the live admin session beneath it.
class _AuthGateHost extends StatelessWidget {
  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  const _AuthGateHost({required this.onGenerateRoute});

  @override
  Widget build(BuildContext context) {
    // One AuthRepository backs both the login bloc and the kiosk cubit's
    // "is the session actually gone?" check (a thin wrapper over the global
    // Supabase client — instance identity doesn't matter).
    final authRepository = AuthRepository();
    return BlocProvider<LoginBloc>(
      create: (_) {
        final bloc = LoginBloc(authRepository: authRepository);
        ApiClient.onUnauthorized = () =>
            bloc.add(const LoginSignOutRequested());
        return bloc;
      },
      child: Builder(
        builder: (context) {
          final loginBloc = context.read<LoginBloc>();
          return BlocProvider<KioskSessionCubit>(
            // Non-lazy: construct the cubit as soon as this host builds — before
            // the authenticated branch first builds its BlocBuilder — so it is
            // already in [KioskStatus.restoring] (and `_restore` already reading
            // localStorage, in parallel with the gym fetch) when the gate first
            // reads it. This guarantees there is no lazy-construct race where an
            // earlier read could observe a pre-restore state and mount the admin
            // workspace.
            lazy: false,
            create: (_) => KioskSessionCubit(
              store: KioskSessionStore(),
              // Anchors the 12h runway to server time (HTTP Date), so a
              // rolled-back device clock can't extend the member surface.
              serverClock: KioskServerClock(),
              dispatchSignOut: () =>
                  loginBloc.add(const LoginSignOutRequested()),
              sessionGone: () =>
                  authRepository.getCurrentUser() == null,
            ),
            child: BlocListener<LoginBloc, LoginState>(
              listenWhen: (_, current) =>
                  current is LoginUnauthenticated,
              listener: (context, _) =>
                  context.read<KioskSessionCubit>().handleSignedOut(),
              child: AuthGate(onGenerateRoute: onGenerateRoute),
            ),
          );
        },
      ),
    );
  }
}

/// Path → screen builder. Same set the old `routes:` map
/// held; matching is done on the URL path only (see
/// [_onGenerateRoute]).
final Map<String, WidgetBuilder> _routeBuilders = {
  AppRoutes.home: (_) => const HomeScreen(),
  AppRoutes.members: (_) => const PeopleScreen(),
  AppRoutes.memberDetail: (_) => const SpecificMemberScreen(),
  AppRoutes.memberAppPreview: (_) => const MemberAppScreen(),
  AppRoutes.memberAppPreviewVideos: (_) =>
      const MemberAppScreen(initialTab: MemberAppTab.videos),
  AppRoutes.memberAppPreviewLoyalty: (_) =>
      const MemberAppScreen(initialTab: MemberAppTab.loyalty),
  AppRoutes.schedule: (_) => const ScheduleScreen(),
  // The Add / Edit Class form is pushed directly from the board
  // (`schedule_screen.dart`) with `BlocProvider.value`, so it shares the
  // board's `ScheduleBloc` and reloads it on save. It has no bloc-less
  // named-route builder here (one would crash with no ancestor bloc).
  AppRoutes.settings: (_) => const SettingsScreen(),
  AppRoutes.videoAgent: (_) => const VideoAgentScreen(),
  AppRoutes.growth: (_) => const GrowthScreen(),
  AppRoutes.employees: (_) =>
      const PeopleScreen(initialTab: PeopleTab.employees),
  AppRoutes.employeeDetail: (_) => const EmployeeDetailScreen(),
};

Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  // Role-based access guard, first thing: if the active role may not open the
  // requested route, resolve the role's landing route instead. Keeping the
  // redirected RouteSettings.name as the landing route makes UrlSyncObserver
  // rewrite the address bar, so a hand-typed forbidden URL (e.g. `/growth` as
  // front desk) visibly lands on the allowed section. A null role
  // (pre-activation) passes through untouched.
  final redirect = redirectRouteFor(settings.name, selectedGym.role);
  if (redirect != null) {
    final builder =
        _routeBuilders[redirect] ?? _routeBuilders[AppRoutes.home]!;
    return MaterialPageRoute<dynamic>(
      builder: builder,
      settings: RouteSettings(name: redirect),
    );
  }
  final path = Uri.parse(settings.name ?? AppRoutes.home).path;
  // A specific member's detail page is deep-linkable by id:
  // `/members/detail/<memberId>`. Parse the id off the path and hand it
  // to SpecificMemberScreen as the route argument (its existing id
  // branch); the bare `/members/detail` (no id) still resolves the first
  // roster member. Keep the path-with-id as the route name so the URL +
  // UrlSyncObserver stay correct.
  final memberId = AppRoutes.memberIdFromPath(path);
  if (memberId != null) {
    return MaterialPageRoute<dynamic>(
      builder: (_) => const SpecificMemberScreen(),
      settings: RouteSettings(name: settings.name, arguments: memberId),
    );
  }
  // The Gym screen's four tabs are each addressable by URL,
  // mapped to the tab the screen opens on.
  const membershipsTabIndex = {
    AppRoutes.memberships: 0,
    AppRoutes.membershipsDiscounts: 1,
    AppRoutes.membershipsWaivers: 2,
    AppRoutes.membershipsRanks: 3,
  };
  final membershipsTab = membershipsTabIndex[path];
  if (membershipsTab != null) {
    return MaterialPageRoute<dynamic>(
      builder: (_) => MembershipsScreen(initialTab: membershipsTab),
      settings: settings,
    );
  }
  // A single main rank's detail page is deep-linkable by id:
  // `/memberships/ranks/detail/<id>`. Parse the id off the path and hand
  // it to RankDetailScreen as the route argument (mirrors member detail);
  // the path-with-id stays the route name so the URL + UrlSyncObserver
  // stay correct.
  final rankId = AppRoutes.mainRankIdFromPath(path);
  if (rankId != null) {
    return MaterialPageRoute<dynamic>(
      builder: (_) => const RankDetailScreen(),
      settings: RouteSettings(name: settings.name, arguments: rankId),
    );
  }
  // A specific employee's detail page is deep-linkable by id:
  // `/employees/detail/<employeeId>`. Parse the id off the path and hand
  // it to EmployeeDetailScreen as the route argument (mirrors member
  // detail); the bare `/employees/detail` (no id) still resolves via the
  // route table. Keep the path-with-id as the route name so the URL +
  // UrlSyncObserver stay correct.
  final employeeId = AppRoutes.employeeIdFromPath(path);
  if (employeeId != null) {
    return MaterialPageRoute<dynamic>(
      builder: (_) => const EmployeeDetailScreen(),
      settings: RouteSettings(name: settings.name, arguments: employeeId),
    );
  }
  // The rank create / edit form carries the rank (or null for create)
  // as a route argument; not deep-linkable.
  if (path == AppRoutes.membershipsRankEditor) {
    final rank = settings.arguments as MainRank?;
    return MaterialPageRoute<dynamic>(
      builder: (_) => EditRankScreen(rank: rank),
      settings: settings,
    );
  }
  // Create / edit a membership plan carries the plan (or null
  // for create) as a route argument.
  if (path == AppRoutes.membershipDetails) {
    final plan = settings.arguments as MembershipPlanResponse?;
    return MaterialPageRoute<dynamic>(
      builder: (_) => MembershipDetailsScreen(plan: plan),
      settings: settings,
    );
  }
  // The waiver editor carries its waiver as a route argument (null =
  // create); not deep-linkable.
  if (path == AppRoutes.membershipsWaiverEditor) {
    final waiver = settings.arguments as WaiverResponse?;
    return MaterialPageRoute<dynamic>(
      builder: (_) => WaiverEditorScreen(waiver: waiver),
      settings: settings,
    );
  }
  // Known path: render its builder as-is (URL unchanged).
  //
  // Unknown path — a stale/typo URL, or an app path with no route builder
  // (e.g. `/schedule/class/new`) — falls back to the ACTIVE ROLE's landing
  // route, NOT blindly Home. Home is the Dashboard, which a trainer or
  // front-desk role is denied, so landing there would strand them off-role
  // (canAccessRoute returns true for unrecognized paths, so the redirect
  // guard above doesn't catch this). Rewrite the address bar to the fallback
  // (mirrors the redirect branch above) so the URL matches the page shown.
  // landingRoute is always one of home/members/schedule (all in
  // _routeBuilders), so the inner `?? AppRoutes.home` is belt-and-braces.
  final knownBuilder = _routeBuilders[path];
  if (knownBuilder != null) {
    return MaterialPageRoute<dynamic>(
      builder: knownBuilder,
      settings: settings,
    );
  }
  final fallback = selectedGym.role?.landingRoute ?? AppRoutes.home;
  return MaterialPageRoute<dynamic>(
    builder: _routeBuilders[fallback] ?? _routeBuilders[AppRoutes.home]!,
    settings: RouteSettings(name: fallback),
  );
}
