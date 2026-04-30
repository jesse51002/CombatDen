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

/// Growth (analytics) screen.
///
/// Figma: file `q04PCZ3W9syMik34JRtRbL`, node `5001:3206`.
/// Stack (top to bottom):
///   1. Total Members hero card (active/inactive arc) — reused from Home
///   2. Four KPI tiles: Total / Trial / New / Lost
///   3. Wide Members card with date-range pill, trend chart, breakdown table
///   4. Two-column row: Monthly Churn + Trial Conversion donut cards
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
            const MembersCard(),
            const _BottomRow(),
          ],
        ),
      ),
    );
  }
}

class _BottomRow extends StatelessWidget {
  const _BottomRow();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          Expanded(
            child: DonutStatsCard(
              title: 'Monthly Churn',
              last30: kMockChurnLast30,
              gymAverage: kMockChurnGymAverage,
              tableValueColumnLabel: 'Churn',
              rows: kMockChurnRows,
            ),
          ),
          Expanded(
            child: DonutStatsCard(
              title: 'Trial Conversion',
              last30: kMockConversionLast30,
              gymAverage: kMockConversionGymAverage,
              tableValueColumnLabel: 'Conversion',
              rows: kMockConversionRows,
            ),
          ),
        ],
      ),
    );
  }
}
