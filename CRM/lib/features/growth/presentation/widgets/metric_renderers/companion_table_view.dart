import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
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

  const ChartWithCompanionTable({
    super.key,
    required this.chart,
    this.table,
  });

  @override
  Widget build(BuildContext context) {
    final t = table;
    if (t == null || t.rows.isEmpty || t.columns.isEmpty) return chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [chart, MetricCompanionTable(table: t)],
    );
  }
}

/// Renders a metric's companion [MetricTable] with the same de-carded
/// typed-column table `member_list` uses, so a chart's data table reads as a
/// sibling of the page's other tables.
///
/// Each cell is formatted by its column's declared type (date → relative
/// date with an absolute tooltip, cents → money, number → right-aligned int,
/// text → left) through the shared `member_list` cell builder, and a null
/// cell renders as an em-dash — never `null` or `0`. Rows are aggregate
/// per-bucket data, not members, so there is no row tap and no row cap: a
/// companion table is bounded by the chart's own buckets.
class MetricCompanionTable extends StatelessWidget {
  final MetricTable table;

  const MetricCompanionTable({super.key, required this.table});

  @override
  Widget build(BuildContext context) {
    if (table.rows.isEmpty || table.columns.isEmpty) {
      return const SizedBox.shrink();
    }
    final columns = table.columns;
    return AppDataTable(
      shrinkWrap: true,
      stickyHeader: false,
      columns: [
        for (final column in columns)
          AppDataTableColumn(
            label: column.label,
            minWidth: minWidthFor(column.type),
            fill: column.type == MemberListColumnType.text ||
                column.type == MemberListColumnType.unknown,
          ),
      ],
      rows: [
        for (final row in table.rows)
          AppDataTableRow(
            cells: [
              for (var i = 0; i < columns.length; i++)
                buildMemberListCell(
                  i < row.cells.length ? row.cells[i] : null,
                  columns[i].type,
                ),
            ],
          ),
      ],
    );
  }
}
