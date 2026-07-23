import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/bounded_metric_table.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/member_list_cells.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

/// A `line` / `bars` chart with its optional companion [MetricTable].
///
/// The chart is always shown; when a table rides along it is composed by
/// [MetricTable.orientation]. `stacked` — the only orientation the backend
/// emits today (Members-over-time, Revenue-over-time) — puts the table
/// beneath the chart. `beside` and the resilient `unknown` fall back to the
/// same stack; a side-by-side row is a localized change here if `beside`
/// ever ships. See `GROWTH_DESIGN.md` §4.9.
class ChartWithCompanionTable extends StatelessWidget {
  /// The rendered chart (legend + plot + notes) — shown with or without a
  /// table.
  final Widget chart;

  /// The companion table, or null when the metric carries none.
  final MetricTable? table;

  /// The chart's bucket granularity (`month` / `week` / `day`), so the
  /// table's `date` column reads in the chart's own units — a monthly
  /// companion table's Month column mirrors the month axis (`Sep 2025`).
  final String granularity;

  const ChartWithCompanionTable({
    super.key,
    required this.chart,
    required this.granularity,
    this.table,
  });

  @override
  Widget build(BuildContext context) {
    final t = table;
    if (t == null || t.rows.isEmpty || t.columns.isEmpty) return chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        chart,
        MetricCompanionTable(table: t, granularity: granularity),
      ],
    );
  }
}

/// The color a companion column's value cells wear, from its `tone` hint —
/// `good` green, `bad` red, `warn` yellow. `neutral`, null and any unknown
/// tone leave the default cell text color (a null return). Restores the old
/// mockup's Gained-green / Lost-red / Retained-yellow read.
Color? columnToneColor(String? tone) => switch (tone) {
      'good' => DesignConstants.goodGreen,
      'bad' => DesignConstants.badRed,
      'warn' => DesignConstants.okYellow,
      _ => null,
    };

/// Renders a metric's companion [MetricTable] with the same de-carded
/// typed-column table `member_list` uses, so a chart's data table reads as a
/// sibling of the page's other tables.
///
/// Columns render equal width (each fills the available space equally) and
/// the whole table is bounded to [DesignConstants.growthTableMaxHeight] with
/// its own internal scroll, so a long per-month breakdown never dictates the
/// tab's height. Each value cell is formatted by its column's declared type
/// (date → absolute date, cents → money, number → right-aligned int, text →
/// left) through the shared `member_list` cell builder, and tinted by its
/// column's `tone`; the Month (date) column stays default. A null cell
/// renders as an em-dash — never `null`, never `0`. Rows are aggregate
/// per-bucket data, not members, so there is no row tap.
class MetricCompanionTable extends StatelessWidget {
  final MetricTable table;

  /// The owning chart's bucket granularity, threaded to the `date` column.
  final String granularity;

  const MetricCompanionTable({
    super.key,
    required this.table,
    required this.granularity,
  });

  @override
  Widget build(BuildContext context) {
    if (table.rows.isEmpty || table.columns.isEmpty) {
      return const SizedBox.shrink();
    }
    final columns = table.columns;
    // Every column is a fill column, so they share the width equally.
    return BoundedMetricTable(
      table: AppDataTable(
        shrinkWrap: true,
        stickyHeader: false,
        columns: [
          for (final column in columns)
            AppDataTableColumn(label: column.label, fill: true),
        ],
        rows: [
          for (final row in table.rows)
            AppDataTableRow(
              cells: [
                for (var i = 0; i < columns.length; i++)
                  buildMemberListCell(
                    i < row.cells.length ? row.cells[i] : null,
                    columns[i].type,
                    granularity: granularity,
                    toneColor: columnToneColor(columns[i].tone),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
