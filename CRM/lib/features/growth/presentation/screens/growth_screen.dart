import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/growth/data/mock_growth.dart';
import 'package:crm/features/growth/presentation/widgets/donut_stats_section/donut_stats_section.dart';
import 'package:crm/features/growth/presentation/widgets/kpi_tiles/kpi_strip.dart';
import 'package:crm/features/growth/presentation/widgets/members_section/members_section.dart';
import 'package:crm/features/home/data/mock_member_stats.dart';
import 'package:crm/features/home/presentation/widgets/total_members_hero/total_members_hero.dart';
import 'package:crm/shared/widgets/app_shell.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// Growth (analytics) screen.
///
/// Sections sit directly on the page, separated by whitespace and thin
/// hairline rules, not boxed in cards.
/// Stack (top to bottom):
///   1. Total Members hero (active/inactive arc) — reused from Home
///   2. KPI stat row: Total / New / Lost, split by vertical rules
///   3. Members section: date-range pill, trend chart, breakdown table
///   4. Monthly Churn donuts + history
class GrowthScreen extends StatelessWidget {
  const GrowthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeRoute: AppRoutes.growth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingBig,
          children: [
            TotalMembersHero(stats: kMockMemberStats),
            KpiStrip(kpis: kMockGrowthKpis),
            const Hairline(),
            const MembersSection(),
            const Hairline(),
            DonutStatsSection(
              title: 'Monthly Churn',
              last30: kMockChurnLast30,
              gymAverage: kMockChurnGymAverage,
              tableValueColumnLabel: 'Churn',
              rows: kMockChurnRows,
            ),
          ],
        ),
      ),
    );
  }
}