import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/home/data/mock_attendance.dart';
import 'package:app_management/features/home/data/mock_member_stats.dart';
import 'package:app_management/features/home/data/mock_upcoming_classes.dart';
import 'package:app_management/features/home/presentation/widgets/live_attendance_card/live_attendance_card.dart';
import 'package:app_management/features/home/presentation/widgets/total_members_hero/total_members_hero.dart';
import 'package:app_management/features/home/presentation/widgets/upcoming_classes_card/upcoming_classes_card.dart';
import 'package:app_management/shared/widgets/app_shell.dart';
import 'package:app_management/shared/widgets/hairline.dart';

/// Admin dashboard / landing screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3823`.
/// Composition (top to bottom):
///   1. "Dashboard" page title
///   2. Total Members hero card (semicircular arc + active/inactive)
///   3. Two-column row of Live Attendance + Upcoming Classes cards
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.home,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Text('Dashboard', style: DesignConstants.big2),
            TotalMembersHero(stats: kMockMemberStats),
            const Hairline(),
            const _DashboardColumns(),
          ],
        ),
      ),
    );
  }
}

class _DashboardColumns extends StatelessWidget {
  const _DashboardColumns();

  @override
  Widget build(BuildContext context) {
    // Equal-height: IntrinsicHeight + stretch resolves the otherwise-
    // infinite vertical constraint from the page scroll view, so both
    // cards size to the taller card's height.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Expanded(
            child: LiveAttendanceCard(entries: kMockLiveAttendance),
          ),
          const Hairline(vertical: true),
          Expanded(
            child: UpcomingClassesCard(dayGroups: kMockUpcomingClasses),
          ),
        ],
      ),
    );
  }
}
