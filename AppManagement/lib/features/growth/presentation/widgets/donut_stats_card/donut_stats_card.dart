import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/features/growth/presentation/widgets/donut_stats_card/_donut_history_table.dart';
import 'package:app_management/features/growth/presentation/widgets/donut_stats_card/_donut_stat.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// "Two donuts + history table" card used on Growth for Monthly Churn.
/// The two donuts sit side by side, with the history table filling the
/// remaining width.
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
    // IntrinsicHeight lets the donuts stretch to the table's height; each
    // donut is kept square (AspectRatio 1) so the rings grow to fill it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          AspectRatio(aspectRatio: 1, child: DonutStat(data: last30)),
          AspectRatio(aspectRatio: 1, child: DonutStat(data: gymAverage)),
          Expanded(
            child: DonutHistoryTable(
              valueColumnLabel: tableValueColumnLabel,
              rows: rows,
            ),
          ),
        ],
      ),
    );
  }
}
