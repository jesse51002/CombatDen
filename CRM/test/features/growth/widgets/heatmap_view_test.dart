import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_density.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_grid_painter.dart';

import 'growth_renderer_fixtures.dart';

void main() {
  group('a null cell is UNKNOWN, never zero', () {
    test('the ramp returns no fill at all for a null cell', () {
      // The load-bearing distinction: an immature cohort has no value, and
      // painting it at the bottom of the scale would read as total churn.
      expect(heatCellFill(null, 20), isNull);
      // A genuine zero is a different fact and does get the no-data step.
      expect(heatCellFill(0, 20), DesignConstants.backgroundAlt);
      expect(heatCellFill(0, 20), isNot(heatCellFill(1, 20)));
    });

    test('a non-null cell climbs the ramp monotonically', () {
      final low = heatCellFill(1, 20)!;
      final high = heatCellFill(20, 20)!;
      expect(low.computeLuminance(), greaterThan(high.computeLuminance()));
    });

    test('a labelled grid caps below the darkest step (AA on the ink)', () {
      expect(heatCellFill(20, 20, labelled: true), heatCellFill(15, 20));
      expect(
        heatCellFill(20, 20, labelled: true),
        isNot(heatCellFill(20, 20)),
      );
    });

    testWidgets('the grid hands the painter the raw null, uncoerced',
        (tester) async {
      await tester.pumpWidget(
        host(
          GrowthMetricView(
            metric: heatmapMetric(
              rows: const ['0-30d', '31-60d'],
              cols: const ['M1', 'M2', 'M3'],
              cells: const [
                [100.0, 82.0, 61.0],
                // This cohort is too young to have reached M2/M3.
                [100.0, null, null],
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<HeatGridPainter>()
          .toList();
      expect(painters, isNotEmpty);
      final cells = painters.first.cells;
      expect(cells[1][1], isNull);
      expect(cells[1][2], isNull);
      expect(cells[0][0], 100.0);
    });

    testWidgets('a labelled cohort grid renders with nulls', (tester) async {
      await tester.pumpWidget(
        host(
          GrowthMetricView(
            metric: heatmapMetric(
              key: 'cohort_retention',
              name: 'Cohort retention',
              rows: const ['Apr', 'May'],
              cols: const ['M1', 'M2', 'M3'],
              cells: const [
                [100.0, 74.0, 55.0],
                [100.0, 71.0, null],
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<HeatGridPainter>()
          .first;
      expect(painter.labelled, isTrue);
      expect(painter.cells[1][2], isNull);
    });
  });
}
