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
///   3. Two-column row (capped at one viewport height): left = Live
///      Attendance over Overdue Payments, each an equal-height half that
///      scrolls on its own (Overdue is the one live, bloc-backed surface
///      here; the rest is mock); right = Upcoming Classes.
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
    // Cap the columns block at one viewport height (the top portion —
    // page title + hero — sits above and is not capped). The right column
    // already self-caps at the viewport; the left column splits that
    // height between Live Attendance and Overdue (see below).
    // `stretch` makes both columns + the divider fill that height.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height,
      ),
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

/// Left dashboard column: Live Attendance and Overdue Payments split the
/// column's (capped) height equally — each is an [Expanded] half that
/// scrolls inside its own [SingleChildScrollView] — separated by a hairline.
class _AttendanceAndOverdue extends StatelessWidget {
  const _AttendanceAndOverdue();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: const [
        // Live Attendance manages its own internal scroll so its footer
        // buttons stay pinned (see LiveAttendanceCard); Overdue has no
        // pinned chrome, so the whole section scrolls.
        Expanded(
          child: LiveAttendanceCard(entries: kMockLiveAttendance),
        ),
        Hairline(),
        Expanded(
          child: SingleChildScrollView(
            child: OverduePaymentsSection(),
          ),
        ),
      ],
    );
  }
}
