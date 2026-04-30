import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/features/growth/presentation/widgets/donut_stats_card/_donut_history_table.dart';
import 'package:app_management/features/growth/presentation/widgets/donut_stats_card/_donut_stat.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// Generic "two donuts + history table" card used twice on Growth:
/// once for Monthly Churn, once for Trial Conversion.
class DonutStatsCard extends StatelessWidget {
  final String title;
  final DonutChartData last30;
  final DonutChartData gymAverage;
  final String tableValueColumnLabel;
  final List<DonutStatRow> rows;

  const DonutStatsCard({
    super.key,
    required this.title,
    required this.last30,
    required this.gymAverage,
    required this.tableValueColumnLabel,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          Text(title, style: DesignConstants.h1),
          _Body(
            last30: last30,
            gymAverage: gymAverage,
            tableValueColumnLabel: tableValueColumnLabel,
            rows: rows,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final DonutChartData last30;
  final DonutChartData gymAverage;
  final String tableValueColumnLabel;
  final List<DonutStatRow> rows;

  const _Body({
    required this.last30,
    required this.gymAverage,
    required this.tableValueColumnLabel,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingBig,
          children: [
            DonutStat(data: last30),
            DonutStat(data: gymAverage),
          ],
        ),
        Expanded(
          child: DonutHistoryTable(
            valueColumnLabel: tableValueColumnLabel,
            rows: rows,
          ),
        ),
      ],
    );
  }
}
