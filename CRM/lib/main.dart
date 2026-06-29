import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/config/environment.dart';
import 'package:crm/core/config/supabase_config.dart';
import 'package:crm/core/constants/env_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/employees/presentation/screens/employee_detail_screen.dart';
import 'package:crm/features/employees/presentation/screens/employees_screen.dart';
import 'package:crm/features/growth/presentation/screens/growth_screen.dart';
import 'package:crm/features/home/presentation/screens/home_screen.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/data/repositories/auth_repository.dart';
import 'package:crm/features/login/presentation/screens/auth_gate.dart';
import 'package:crm/features/members/presentation/screens/member_app_screen.dart';
import 'package:crm/features/members/presentation/screens/members_screen.dart';
import 'package:crm/features/members/presentation/screens/specific_member_screen.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/memberships/data/models/waiver_response.dart';
import 'package:crm/features/memberships/presentation/screens/membership_details_screen.dart';
import 'package:crm/features/memberships/presentation/screens/memberships_screen.dart';
import 'package:crm/features/memberships/presentation/screens/waiver_editor_screen.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:crm/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:crm/features/settings/presentation/screens/settings_screen.dart';
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

/// Provides [LoginBloc] above the [AuthGate] and wires the
/// 401 escape hatch: when the API client gives up on a
/// request (refresh failed), sign the session out so the
/// gate drops back to the login screen.
class _AuthGateHost extends StatelessWidget {
  final Route<dynamic> Function(RouteSettings) onGenerateRoute;

  const _AuthGateHost({required this.onGenerateRoute});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginBloc>(
      create: (_) {
        final bloc = LoginBloc(authRepository: AuthRepository());
        ApiClient.onUnauthorized = () =>
            bloc.add(const LoginSignOutRequested());
        return bloc;
      },
      child: AuthGate(onGenerateRoute: onGenerateRoute),
    );
  }
}

/// Path → screen builder. Same set the old `routes:` map
/// held; matching is done on the URL path only (see
/// [_onGenerateRoute]).
final Map<String, WidgetBuilder> _routeBuilders = {
  AppRoutes.home: (_) => const HomeScreen(),
  AppRoutes.members: (_) => const MembersScreen(),
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
  AppRoutes.growth: (_) => const GrowthScreen(),
  AppRoutes.employees: (_) => const EmployeesScreen(),
  AppRoutes.employeeDetail: (_) => const EmployeeDetailScreen(),
};

Route<dynamic> _onGenerateRoute(RouteSettings settings) {
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
  // The Memberships screen's three tabs are each addressable by URL,
  // mapped to the tab the screen opens on.
  const membershipsTabIndex = {
    AppRoutes.memberships: 0,
    AppRoutes.membershipsDiscounts: 1,
    AppRoutes.membershipsWaivers: 2,
  };
  final membershipsTab = membershipsTabIndex[path];
  if (membershipsTab != null) {
    return MaterialPageRoute<dynamic>(
      builder: (_) => MembershipsScreen(initialTab: membershipsTab),
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
  final builder =
      _routeBuilders[path] ?? _routeBuilders[AppRoutes.home]!;
  return MaterialPageRoute<dynamic>(
    builder: builder,
    settings: settings,
  );
}
