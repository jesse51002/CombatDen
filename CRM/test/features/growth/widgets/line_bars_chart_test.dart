import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/series_line_painter.dart';

import 'growth_renderer_fixtures.dart';

/// A single-series count line shaped like the real `members_trend`: a
/// cumulative member count climbing from 2 to 107 over eleven months.
GrowthMetric _membersTrendLike() => lineMetric(
      series: const [
        MetricSeries(
          key: 'active',
          label: 'Active Members',
          points: [
            SeriesPoint(date: '2025-09-01', value: 2),
            SeriesPoint(date: '2025-10-01', value: 6),
            SeriesPoint(date: '2025-11-01', value: 6),
            SeriesPoint(date: '2025-12-01', value: 6),
            SeriesPoint(date: '2026-01-01', value: 7),
            SeriesPoint(date: '2026-02-01', value: 9),
            SeriesPoint(date: '2026-03-01', value: 9),
            SeriesPoint(date: '2026-04-01', value: 14),
            SeriesPoint(date: '2026-05-01', value: 19),
            SeriesPoint(date: '2026-06-01', value: 22),
            SeriesPoint(date: '2026-07-01', value: 107),
          ],
        ),
      ],
    );

/// Two weekly series whose newest bucket is a still-filling week — the exact
/// shape the misleading legend bug lived on: the latest Check-ins bucket is 0
/// while the window total is 95.
GrowthMetric _incompleteWeekLine() => lineMetric(
      series: const [
        MetricSeries(
          key: 'signups',
          label: 'Sign-ups',
          points: [
            SeriesPoint(date: '2026-06-29', value: 20),
            SeriesPoint(date: '2026-07-06', value: 30),
            SeriesPoint(date: '2026-07-13', value: 14),
          ],
        ),
        MetricSeries(
          key: 'checkins',
          label: 'Check-ins',
          points: [
            SeriesPoint(date: '2026-06-29', value: 40),
            SeriesPoint(date: '2026-07-06', value: 55),
            SeriesPoint(date: '2026-07-13', value: 0),
          ],
        ),
      ],
    );

SeriesLinePainter _linePainter(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<SeriesLinePainter>()
      .toList();
  expect(painters, isNotEmpty, reason: 'no SeriesLinePainter was mounted');
  return painters.first;
}

void main() {
  Future<void> pump(WidgetTester tester, GrowthMetric metric) =>
      tester.pumpWidget(host(GrowthMetricView(metric: metric)));

  group('line scale (a blank line / negative axis would fail here)', () {
    testWidgets('the painter receives non-empty points on a non-negative scale',
        (tester) async {
      await pump(tester, _membersTrendLike());
      final painter = _linePainter(tester);

      // Non-empty points must reach the painter, or the line is blank.
      expect(painter.series, isNotEmpty);
      expect(
        painter.series.any((s) => s.values.any((v) => v != null)),
        isTrue,
        reason: 'the line painter got only null points -> a blank line',
      );

      // A count / cents line axis is 0..niceCeiling(max): never negative.
      // Negatives belong only to a diverging bars chart.
      expect(painter.maxY, greaterThanOrEqualTo(0));
      expect(
        painter.gridTicks,
        everyElement(greaterThanOrEqualTo(0)),
        reason: 'a count line must not carry a negative axis tick',
      );
    });

    testWidgets('the axis is 0..niceCeiling(max) — 200/100/0 for a max of 107',
        (tester) async {
      await pump(tester, _membersTrendLike());
      final painter = _linePainter(tester);
      expect(painter.maxY, 200);
      expect(painter.gridTicks, [200, 100, 0]);
    });
  });

  group('legend value = sum over the shown range, not the last bucket', () {
    testWidgets('a line legend sums each series over the visible window',
        (tester) async {
      // Sign-ups 20+30+14 = 64 ; Check-ins 40+55+0 = 95. The newest bucket
      // (Sign-ups 14, Check-ins 0) is a still-filling week — showing it beside
      // a full chart is the bug this guards.
      await pump(tester, _incompleteWeekLine());

      expect(find.text('Sign-ups 64'), findsOneWidget);
      expect(find.text('Check-ins 95'), findsOneWidget);

      // The old, misleading last-bucket values must be gone.
      expect(find.text('Sign-ups 14'), findsNothing);
      expect(find.text('Check-ins 0'), findsNothing);
    });

    testWidgets('a bars legend sums over the shown range too', (tester) async {
      // The default two-series bars fixture: Check-ins 120+141+133 = 394 ;
      // Sign-ups 150+160+155 = 465.
      await pump(tester, barsMetric());
      expect(find.text('Check-ins 394'), findsOneWidget);
      expect(find.text('Sign-ups 465'), findsOneWidget);
      expect(find.text('Check-ins 133'), findsNothing);
      expect(find.text('Sign-ups 155'), findsNothing);
    });
  });
}
