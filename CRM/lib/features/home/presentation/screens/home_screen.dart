import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/home/data/mock_attendance.dart';
import 'package:crm/features/home/data/mock_member_stats.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_card.dart';
import 'package:crm/features/home/presentation/widgets/overdue_payments/overdue_payments_section.dart';
import 'package:crm/features/home/presentation/widgets/total_members_hero/total_members_hero.dart';
import 'package:crm/features/home/presentation/widgets/upcoming_classes_card/upcoming_classes_card.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Admin dashboard / landing screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3823`.
/// Composition (top to bottom):
///   1. "Dashboard" page title
///   2. Total Members hero card (semicircular arc + active/inactive)
///   3. Two-column row: left = Live Attendance + Overdue Payments
///      stacked (Overdue is the one live, bloc-backed surface here;
///      the rest is mock); right = Upcoming Classes.
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
    // columns size to the taller column's height.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          const Expanded(child: _AttendanceAndOverdue()),
          const Hairline(vertical: true),
          const Expanded(
            child: UpcomingClassesCard(),
          ),
        ],
      ),
    );
  }
}

/// Left dashboard column: Live Attendance stacked above Overdue Payments,
/// separated by a hairline.
class _AttendanceAndOverdue extends StatelessWidget {
  const _AttendanceAndOverdue();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        LiveAttendanceCard(entries: kMockLiveAttendance),
        const Hairline(),
        const OverduePaymentsSection(),
      ],
    );
  }
}
