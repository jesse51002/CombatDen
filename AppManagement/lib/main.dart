import 'package:flutter/material.dart';

import 'package:app_management/core/navigation/app_routes.dart';
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
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      initialRoute: AppRoutes.home,
      routes: {
        AppRoutes.home: (_) => const HomeScreen(),
        AppRoutes.members: (_) => const MembersScreen(),
        AppRoutes.memberDetail: (_) => const SpecificMemberScreen(),
        AppRoutes.memberAppPreview: (_) => const MemberAppScreen(),
        AppRoutes.schedule: (_) => const ScheduleScreen(),
        AppRoutes.scheduleAddClass: (_) => const ClassFormScreen(),
        AppRoutes.scheduleEditClass: (_) =>
            ClassFormScreen(existing: kSampleClass),
        AppRoutes.qrCodes: (_) => const QrCodesScreen(),
        AppRoutes.growth: (_) => const GrowthScreen(),
      },
    );
  }
}
