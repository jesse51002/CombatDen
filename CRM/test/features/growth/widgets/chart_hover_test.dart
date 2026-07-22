import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_hover_layer.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_readout_card.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/heat_grid_painter.dart';

import 'growth_renderer_fixtures.dart';

void main() {
  /// Moves a MOUSE pointer onto [target] — this is a web app, so the
  /// read-out is hover-driven, not tap-driven.
  Future<void> hoverOver(WidgetTester tester, Offset at) async {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();
    await pointer.moveTo(at);
    await tester.pumpAndSettle();
  }

  testWidgets('hovering a line chart reads out the bucket under the pointer',
      (tester) async {
    await tester.pumpWidget(host(GrowthMetricView(metric: lineMetric())));
    expect(find.byType(ChartReadoutCard), findsNothing);

    // The newest bucket sits at the plot's right edge.
    final plot = tester.getRect(find.byType(ChartHoverLayer));
    await hoverOver(tester, Offset(plot.right - 2, plot.center.dy));

    expect(find.byType(ChartReadoutCard), findsOneWidget);
    // The read-out names the bucket and both series' exact values.
    expect(find.text('Jul 2026'), findsOneWidget);
    expect(find.text('133'), findsOneWidget);
    expect(find.text('155'), findsOneWidget);
  });

  testWidgets('hovering a bar chart reads out its bucket too', (tester) async {
    await tester.pumpWidget(host(GrowthMetricView(metric: barsMetric())));
    final plot = tester.getRect(find.byType(ChartHoverLayer));
    await hoverOver(tester, Offset(plot.left + 4, plot.center.dy));

    expect(find.byType(ChartReadoutCard), findsOneWidget);
    expect(find.text('May 2026'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('hovering a heat cell with no value says so', (tester) async {
    await tester.pumpWidget(
      host(
        GrowthMetricView(
          metric: heatmapMetric(
            key: 'cohort_retention',
            rows: const ['Apr'],
            cols: const ['M1', 'M2'],
            cells: const [
              [100.0, null],
            ],
          ),
        ),
      ),
    );
    final grid = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is HeatGridPainter,
      ),
    );
    // The second column of the only row is the null cell.
    await hoverOver(tester, Offset(grid.right - 8, grid.bottom - 8));

    expect(find.byType(ChartReadoutCard), findsOneWidget);
    expect(find.text('Not recorded yet'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
