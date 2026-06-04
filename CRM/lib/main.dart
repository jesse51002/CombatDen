import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'package:crm/core/config/environment.dart';
import 'package:crm/core/config/supabase_config.dart';
import 'package:crm/core/constants/env_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/network/api_client.dart';
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
import 'package:crm/features/qr_codes/presentation/screens/qr_codes_screen.dart';
import 'package:crm/features/schedule/data/mock_schedule.dart';
import 'package:crm/features/schedule/presentation/screens/class_form_screen.dart';
import 'package:crm/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:crm/shared/themes/app_theme.dart';

Future<void> main() async {
  // Bring up the backend stack before the first frame.
  // Each step is best-effort: a failure is logged and the
  // app still boots (degraded), so a missing key or an
  // offline Supabase never leaves a blank screen — the auth
  // gate then shows the login screen instead.
  WidgetsFlutterBinding.ensureInitialized();

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

class AppManagementRoot extends StatelessWidget {
  const AppManagementRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CombatDen Admin',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
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
  AppRoutes.scheduleAddClass: (_) => const ClassFormScreen(),
  // scheduleEditClass is handled in `_onGenerateRoute` so it
  // can read the tapped class off `settings.arguments` (a
  // `WidgetBuilder` can't see them).
  AppRoutes.qrCodes: (_) => const QrCodesScreen(),
  AppRoutes.growth: (_) => const GrowthScreen(),
  AppRoutes.employees: (_) => const EmployeesScreen(),
  AppRoutes.employeeDetail: (_) => const EmployeeDetailScreen(),
};

Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  final path = Uri.parse(settings.name ?? AppRoutes.home).path;
  // Edit Class carries the tapped class as a route argument;
  // fall back to the sample for a direct nav (e.g. deep link)
  // with no argument.
  if (path == AppRoutes.scheduleEditClass) {
    final existing =
        settings.arguments as ScheduleClass? ?? kSampleClass;
    return MaterialPageRoute<dynamic>(
      builder: (_) => ClassFormScreen(existing: existing),
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
