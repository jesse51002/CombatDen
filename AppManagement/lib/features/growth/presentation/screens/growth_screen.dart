import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/features/growth/presentation/widgets/donut_stats_card/donut_stats_card.dart';
import 'package:app_management/features/growth/presentation/widgets/kpi_tiles/kpi_strip.dart';
import 'package:app_management/features/growth/presentation/widgets/members_card/members_card.dart';
import 'package:app_management/features/home/data/mock_member_stats.dart';
import 'package:app_management/features/home/presentation/widgets/total_members_card/total_members_card.dart';
import 'package:app_management/shared/widgets/app_shell.dart';
import 'package:app_management/shared/widgets/hairline.dart';

/// Growth (analytics) screen.
///
/// Sections sit directly on the page, separated by whitespace and thin
/// hairline rules — not boxed in cards. Only the Total Members hero (reused
/// from Home) is still carded for now.
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
            TotalMembersCard(stats: kMockMemberStats),
            KpiStrip(kpis: kMockGrowthKpis),
            const Hairline(),
            const MembersCard(),
            const Hairline(),
            DonutStatsCard(
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