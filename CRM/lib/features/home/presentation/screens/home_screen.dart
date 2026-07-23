import 'package:flutter/material.dart';

import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/growth/presentation/widgets/revenue_hero_card.dart';
import 'package:crm/features/growth/presentation/widgets/revenue_trend_card.dart';
import 'package:crm/features/home/presentation/widgets/live_attendance_card/live_attendance_card.dart';
import 'package:crm/features/home/presentation/widgets/overdue_payments/overdue_payments_section.dart';
import 'package:crm/features/home/presentation/widgets/upcoming_classes_card/upcoming_classes_card.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Admin dashboard / landing screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `3132:3823`.
/// Composition (top to bottom):
///   1. "Dashboard" page title
///   2. The money half-pie — the live `revenue_hero` growth metric, the
///      same figure Growth's Overview tab leads with
///   3. Two-column row (capped at one viewport height): left = Live
///      Attendance over Overdue Payments, each an equal-height half that
///      scrolls on its own; right = Upcoming Classes.
///
/// Every section is live and bloc-backed: the hero reads the growth
/// metrics, Live Attendance + Upcoming read the `/classes/instances`
/// schedule feed, and Overdue reads the members list.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // The money half-pie AND the recurring-revenue trend are OVERVIEW/
    // analytics cards showing gym revenue — owner/admin only (front desk must
    // not see the gym's money). Front desk still reaches the Dashboard for its
    // operational cards (Live Attendance, Overdue Payments, Upcoming Classes),
    // which stay unconditional below. The revenue cards' trailing hairlines go
    // with them so front desk doesn't get a stray divider under the title.
    final showHero = selectedGym.role?.canViewGymAnalytics ?? false;
    return AppShell(
      activeRoute: AppRoutes.home,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            Text('Dashboard', style: DesignConstants.big2),
            if (showHero) ...[
              const RevenueHeroCard(),
              const Hairline(),
              const RevenueTrendCard(),
              const Hairline(),
            ],
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
          child: LiveAttendanceCard(),
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
