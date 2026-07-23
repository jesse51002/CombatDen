import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/companion_table_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/line_view.dart';
import 'package:crm/shared/widgets/app_data_table.dart';

import 'growth_renderer_fixtures.dart';

/// A companion table with one of every column type plus a null cell, so a
/// single fixture exercises date / number / cents / null formatting.
MetricTable _table({
  TableOrientation orientation = TableOrientation.stacked,
}) =>
    MetricTable(
      orientation: orientation,
      columns: const [
        MetricTableColumn(
          key: 'month',
          label: 'Month',
          type: MemberListColumnType.date,
        ),
        MetricTableColumn(
          key: 'gained',
          label: 'Gained',
          type: MemberListColumnType.number,
        ),
        MetricTableColumn(
          key: 'collected',
          label: 'Collected',
          type: MemberListColumnType.cents,
        ),
      ],
      rows: const [
        MetricTableRow(cells: ['2026-06-01', 6.0, 250000.0]),
        // A null cents cell: an absent amount, not zero.
        MetricTableRow(cells: ['2026-07-01', 85.0, null]),
      ],
    );

GrowthMetric _lineWithTable({MetricTable? table}) => GrowthMetric(
      key: 'members_trend',
      name: 'Members over time',
      categories: const [GrowthCategory.members],
      type: GrowthMetricType.line,
      order: 10,
      computedAt: DateTime.utc(2026, 7, 20, 14),
      data: LineData(
        unit: MetricUnit.count,
        granularity: 'month',
        series: const [
          MetricSeries(
            key: 'active',
            label: 'Active',
            points: [
              SeriesPoint(date: '2026-06-01', value: 22),
              SeriesPoint(date: '2026-07-01', value: 107),
            ],
          ),
        ],
        table: table,
      ),
    );

void main() {
  Future<void> pump(WidgetTester tester, GrowthMetric metric) =>
      tester.pumpWidget(host(GrowthMetricView(metric: metric)));

  group('companion table', () {
    testWidgets('renders beneath the chart when the metric carries one',
        (tester) async {
      await pump(tester, _lineWithTable(table: _table()));
      expect(tester.takeException(), isNull);

      // The chart is still shown, with the table wrapped alongside it.
      expect(find.byType(LineView), findsOneWidget);
      final wrap = find.byType(ChartWithCompanionTable);
      expect(wrap, findsOneWidget);
      expect(
        find.descendant(of: wrap, matching: find.byType(MetricCompanionTable)),
        findsOneWidget,
      );
      expect(find.byType(AppDataTable), findsOneWidget);
    });

    testWidgets('formats each cell by its column type', (tester) async {
      await pump(tester, _lineWithTable(table: _table()));

      // number → grouped int; cents → money; a null cell → em-dash, not "0".
      expect(find.text('6'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);
      expect(
        find.text(formatMinorUnits(250000, decimalDigits: 0)),
        findsOneWidget,
      );
      // The null cents cell reads as an em-dash — never "null", never "0".
      // ("0" is not asserted absent: the chart's own y-axis carries a 0 tick.)
      expect(find.text('—'), findsOneWidget);
      expect(find.text('null'), findsNothing);

      // The column headers come through.
      expect(find.text('Gained'), findsOneWidget);
      expect(find.text('Collected'), findsOneWidget);
    });

    testWidgets('no table means no companion table', (tester) async {
      await pump(tester, _lineWithTable());
      expect(find.byType(LineView), findsOneWidget);
      expect(find.byType(MetricCompanionTable), findsNothing);
      expect(find.byType(AppDataTable), findsNothing);
    });

    testWidgets('an empty table is dropped, the chart stays', (tester) async {
      await pump(
        tester,
        _lineWithTable(
          table: const MetricTable(
            orientation: TableOrientation.stacked,
            columns: [],
            rows: [],
          ),
        ),
      );
      expect(find.byType(LineView), findsOneWidget);
      expect(find.byType(MetricCompanionTable), findsNothing);
    });

    testWidgets('beside and unknown orientations fall back to a stack',
        (tester) async {
      for (final orientation in [
        TableOrientation.beside,
        TableOrientation.unknown,
      ]) {
        await pump(
          tester,
          _lineWithTable(table: _table(orientation: orientation)),
        );
        expect(tester.takeException(), isNull);
        // Stacked layout: the chart and the table share a Column, top to
        // bottom, inside the wrapper (never a side-by-side Row today).
        final wrap = find.byType(ChartWithCompanionTable);
        expect(
          find.descendant(of: wrap, matching: find.byType(Column)),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: wrap,
            matching: find.byType(MetricCompanionTable),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('a bars metric carries a companion table too', (tester) async {
      await pump(
        tester,
        barsMetric().copyWithTable(_table()),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(MetricCompanionTable), findsOneWidget);
    });
  });
}

/// Small test-only helper: re-wrap a fixture bars metric with a table.
extension on GrowthMetric {
  GrowthMetric copyWithTable(MetricTable table) {
    final bars = data as BarsData;
    return GrowthMetric(
      key: key,
      name: name,
      categories: categories,
      type: type,
      order: order,
      computedAt: computedAt,
      data: BarsData(
        unit: bars.unit,
        granularity: bars.granularity,
        series: bars.series,
        byClass: bars.byClass,
        table: table,
      ),
    );
  }
}
