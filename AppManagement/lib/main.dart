import 'package:flutter/material.dart';

import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/employees/presentation/screens/employee_detail_screen.dart';
import 'package:app_management/features/employees/presentation/screens/employees_screen.dart';
import 'package:app_management/features/growth/presentation/screens/growth_screen.dart';
import 'package:app_management/features/home/presentation/screens/home_screen.dart';
import 'package:app_management/features/members/presentation/screens/member_app_screen.dart';
import 'package:app_management/features/members/presentation/screens/members_screen.dart';
import 'package:app_management/features/members/presentation/screens/specific_member_screen.dart';
import 'package:app_management/features/qr_codes/presentation/screens/qr_codes_screen.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/features/schedule/presentation/screens/class_form_screen.dart';
import 'package:app_management/features/schedule/presentation/screens/schedule_screen.dart';
import 'package:app_management/shared/themes/app_theme.dart';

void main() => runApp(const AppManagementRoot());

class AppManagementRoot extends StatelessWidget {
  const AppManagementRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CombatDen Admin',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      initialRoute: AppRoutes.home,
      // `onGenerateRoute` (rather than a `routes:` map) so a route name can
      // carry a query string and still resolve. The theme preview deep-links
      // the previewed theme as `…/app-preview?theme=…`; we match on the path
      // and the screen reads the query off `Uri.base`.
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

/// Path → screen builder. Same set the old `routes:` map held; matching is
/// done on the URL path only (see [_onGenerateRoute]).
final Map<String, WidgetBuilder> _routeBuilders = {
  AppRoutes.home: (_) => const HomeScreen(),
  AppRoutes.members: (_) => const MembersScreen(),
  AppRoutes.memberDetail: (_) => const SpecificMemberScreen(),
  AppRoutes.memberAppPreview: (_) => const MemberAppScreen(),
  AppRoutes.schedule: (_) => const ScheduleScreen(),
  AppRoutes.scheduleAddClass: (_) => const ClassFormScreen(),
  // scheduleEditClass is handled in `_onGenerateRoute` so it can read the
  // tapped class off `settings.arguments` (a `WidgetBuilder` can't see them).
  AppRoutes.qrCodes: (_) => const QrCodesScreen(),
  AppRoutes.growth: (_) => const GrowthScreen(),
  AppRoutes.employees: (_) => const EmployeesScreen(),
  AppRoutes.employeeDetail: (_) => const EmployeeDetailScreen(),
};

Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  final path = Uri.parse(settings.name ?? AppRoutes.home).path;
  // Edit Class carries the tapped class as a route argument; fall back to the
  // sample for a direct nav (e.g. deep link) with no argument.
  if (path == AppRoutes.scheduleEditClass) {
    final existing = settings.arguments as ScheduleClass? ?? kSampleClass;
    return MaterialPageRoute<dynamic>(
      builder: (_) => ClassFormScreen(existing: existing),
      settings: settings,
    );
  }
  final builder = _routeBuilders[path] ?? _routeBuilders[AppRoutes.home]!;
  return MaterialPageRoute<dynamic>(builder: builder, settings: settings);
}
