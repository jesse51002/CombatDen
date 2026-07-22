import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/bars_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/breakdown_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/donut_pair_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/hero_split_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/heatmap_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/kpi_group_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/line_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/member_list_view.dart';
import 'package:crm/shared/widgets/empty_state.dart';

import 'growth_renderer_fixtures.dart';

void main() {
  Future<void> pumpMetric(WidgetTester tester, GrowthMetric metric) =>
      tester.pumpWidget(host(GrowthMetricView(metric: metric)));

  group('dispatch', () {
    testWidgets('every payload subtype reaches its own renderer',
        (tester) async {
      final expected = <GrowthMetric, Type>{
        kpiMetric(): KpiGroupView,
        heroMetric(): HeroSplitView,
        lineMetric(): LineView,
        barsMetric(): BarsView,
        breakdownMetric(): BreakdownView,
        donutMetric(): DonutPairView,
        heatmapMetric(): HeatmapView,
        memberListMetric(): MemberListView,
      };
      for (final entry in expected.entries) {
        await pumpMetric(tester, entry.key);
        expect(
          find.byType(entry.value),
          findsOneWidget,
          reason: '${entry.key.type} did not reach ${entry.value}',
        );
      }
    });
  });

  group('populated renderers build', () {
    final populated = <String, GrowthMetric>{
      'kpi_group': kpiMetric(),
      'hero_split': heroMetric(),
      'line': lineMetric(),
      'bars': barsMetric(),
      'breakdown': breakdownMetric(),
      'donut_pair': donutMetric(),
      'heatmap': heatmapMetric(),
      'member_list': memberListMetric(),
    };
    for (final entry in populated.entries) {
      testWidgets('${entry.key} renders without throwing', (tester) async {
        await pumpMetric(tester, entry.value);
        expect(tester.takeException(), isNull);
        expect(find.byType(EmptyState), findsNothing);
      });
    }
  });

  group('empty renderers', () {
    // A metric with no rows is NORMAL — a young gym, not a failure — so
    // every renderer owns a zero-data state rather than blanking.
    final empties = <String, GrowthMetric>{
      'kpi_group': kpiMetric(tiles: const []),
      'line': lineMetric(series: const []),
      'bars': barsMetric(series: const []),
      'breakdown': breakdownMetric(items: const []),
      'donut_pair': donutMetric(donuts: const []),
      'heatmap': heatmapMetric(rows: const [], cells: const []),
      'member_list': memberListMetric(rows: const []),
    };
    for (final entry in empties.entries) {
      testWidgets('${entry.key} renders an empty state', (tester) async {
        await pumpMetric(tester, entry.value);
        expect(tester.takeException(), isNull);
        expect(find.byType(EmptyState), findsOneWidget);
      });
    }

    testWidgets('hero_split keeps its figure and explains the zero',
        (tester) async {
      // The hero is the page's one figure: it still draws its empty track,
      // with the copy standing in for the legend.
      await pumpMetric(tester, heroMetric(segments: const [], total: 0));
      expect(tester.takeException(), isNull);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Nothing billed this month yet'), findsOneWidget);
    });
  });

  group('empty copy', () {
    testWidgets('a line names the metric it is missing', (tester) async {
      await pumpMetric(
        tester,
        lineMetric(series: const [], name: 'Members over time'),
      );
      expect(find.text('No Members over time history yet'), findsOneWidget);
    });

    testWidgets('a bounded member list gets its own copy', (tester) async {
      await pumpMetric(
        tester,
        memberListMetric(rows: const [], key: 'at_risk_members'),
      );
      expect(find.text('Nobody is at risk right now'), findsOneWidget);
    });
  });
}
