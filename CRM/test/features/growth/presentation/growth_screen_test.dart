import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/growth/bloc/growth_bloc.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/screens/growth_screen.dart';
import 'package:crm/features/growth/presentation/tabs/attendance_tab.dart';
import 'package:crm/features/growth/presentation/tabs/members_tab.dart';
import 'package:crm/features/growth/presentation/tabs/overview_tab.dart';
import 'package:crm/features/growth/presentation/tabs/retention_tab.dart';
import 'package:crm/features/growth/presentation/tabs/revenue_tab.dart';
import 'package:crm/features/growth/presentation/tabs/trial_tab.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/empty_state.dart';
import 'package:crm/shared/widgets/hairline.dart';

class _MockGrowthBloc extends MockBloc<GrowthEvent, GrowthState>
    implements GrowthBloc {}

final DateTime _computedAt = DateTime.utc(2026, 7, 20, 14);

GrowthMetric _metric({
  required String key,
  required String name,
  required GrowthCategory category,
  required GrowthMetricType type,
  required GrowthMetricData data,
  int order = 10,
}) =>
    GrowthMetric(
      key: key,
      name: name,
      categories: [category],
      type: type,
      order: order,
      computedAt: _computedAt,
      data: data,
    );

GrowthMetric _breakdown(
  GrowthCategory category,
  String name, {
  String? key,
  int order = 10,
}) =>
    _metric(
      key: key ?? '${category.value}_breakdown',
      order: order,
      name: name,
      category: category,
      type: GrowthMetricType.breakdown,
      data: const BreakdownData(
        unit: MetricUnit.count,
        items: [BreakdownItem(key: 'a', label: 'Unlimited', value: 12)],
      ),
    );

/// 24 monthly points ending 2026-07-01, so a 3M window keeps exactly the
/// four buckets Apr…Jul.
List<SeriesPoint> _monthlyPoints() => [
      for (var i = 23; i >= 0; i--)
        SeriesPoint(
          date: DateTime(2026, 7 - i).toIso8601String().substring(0, 10),
          value: (i + 1).toDouble(),
        ),
    ];

GrowthMetric _lineMetric({
  GrowthCategory category = GrowthCategory.overview,
  String name = 'Overview trend',
  List<ClassSeries>? byClass,
}) =>
    _metric(
      key: '${category.value}_trend',
      name: name,
      category: category,
      type: GrowthMetricType.line,
      order: 20,
      data: LineData(
        unit: MetricUnit.count,
        granularity: 'month',
        series: [
          MetricSeries(
            key: 'total',
            label: 'Total',
            points: _monthlyPoints(),
          ),
        ],
        byClass: byClass,
      ),
    );

/// A half-span `bars` chart. Its key (`promotions_trend` /
/// `redemptions_trend`) is one the span registry marks half, so two in a
/// row pair into one Row — and `bars` renders through a `LayoutBuilder`,
/// the combination that used to crash under `IntrinsicHeight`.
GrowthMetric _barsMetric({
  required String key,
  required String name,
  GrowthCategory category = GrowthCategory.overview,
  int order = 10,
}) =>
    _metric(
      key: key,
      name: name,
      category: category,
      type: GrowthMetricType.bars,
      order: order,
      data: BarsData(
        unit: MetricUnit.count,
        granularity: 'month',
        series: [
          MetricSeries(key: 'n', label: 'Count', points: _monthlyPoints()),
        ],
      ),
    );

GrowthState _loaded(List<GrowthMetric> metrics) => GrowthState(
      status: GrowthStatus.loaded,
      metrics: metrics,
      computedAt: _computedAt,
    );

/// One metric per tab, each named after its tab.
List<GrowthMetric> _oneMetricPerTab() => [
      _breakdown(GrowthCategory.overview, 'Overview stat'),
      _breakdown(GrowthCategory.members, 'Members stat'),
      _breakdown(GrowthCategory.revenue, 'Revenue stat'),
      _breakdown(GrowthCategory.attendance, 'Attendance stat'),
      _breakdown(GrowthCategory.trial, 'Trial stat'),
      _breakdown(GrowthCategory.retention, 'Retention stat'),
    ];

void main() {
  late _MockGrowthBloc bloc;

  setUp(() => bloc = _MockGrowthBloc());

  Future<void> pump(
    WidgetTester tester,
    GrowthState state, {
    int initialTab = 0,
  }) async {
    // A desktop viewport: below navMobileBreakpoint the page renders its
    // compact layout, which is not what these tests are about.
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    whenListen(bloc, const Stream<GrowthState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<GrowthBloc>.value(
            value: bloc,
            child: GrowthView(initialTab: initialTab),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  int? tabIndex(WidgetTester tester) =>
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

  group('tabs', () {
    testWidgets('every tab renders its own category, in order',
        (tester) async {
      await pump(tester, _loaded(_oneMetricPerTab()));

      // The IndexedStack keeps every tab mounted but only the open one is
      // visible (and findable), so walk them.
      final expected = <String, (Type, String)>{
        'Overview': (OverviewTab, 'Overview stat'),
        'Members': (MembersTab, 'Members stat'),
        'Revenue': (RevenueTab, 'Revenue stat'),
        'Attendance': (AttendanceTab, 'Attendance stat'),
        'Trial': (TrialTab, 'Trial stat'),
        'Retention': (RetentionTab, 'Retention stat'),
      };
      for (final entry in expected.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pump();
        final (tab, metricName) = entry.value;
        expect(
          find.descendant(
            of: find.byType(tab),
            matching: find.text(metricName),
          ),
          findsOneWidget,
          reason: '$tab did not render $metricName',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tab with no metrics shows an empty state', (tester) async {
      await pump(
        tester,
        _loaded([_breakdown(GrowthCategory.overview, 'Overview stat')]),
      );
      await tester.tap(find.text('Members'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(MembersTab),
          matching: find.byType(EmptyState),
        ),
        findsOneWidget,
      );
    });

    testWidgets('two consecutive half-span metrics share one row',
        (tester) async {
      // `breakdown` is the one half-span type; a pair renders side by side
      // in one Row separated by whitespace — no vertical divider (which would
      // force an IntrinsicHeight that a chart child can't be measured under),
      // and no horizontal rule (that only goes BETWEEN rows).
      await pump(
        tester,
        _loaded([
          _breakdown(GrowthCategory.overview, 'Status mix', key: 'mix'),
          _breakdown(
            GrowthCategory.overview,
            'Member tenure',
            key: 'member_tenure',
            order: 20,
          ),
        ]),
      );
      expect(find.text('Status mix'), findsOneWidget);
      expect(find.text('Member tenure'), findsOneWidget);
      // Both sit under one Row (the pair), so that Row is an ancestor of both.
      final sharedRow = find.ancestor(
        of: find.text('Status mix'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: sharedRow, matching: find.text('Member tenure')),
        findsWidgets,
      );
      // A single paired row: no inter-row rule, and no vertical divider.
      expect(
        find.descendant(
          of: find.byType(OverviewTab),
          matching: find.byType(Hairline),
        ),
        findsNothing,
      );
    });

    testWidgets('a paired row of chart metrics renders without crashing',
        (tester) async {
      // The regression this guards: two half-span CHART metrics
      // (bars → chart_frame → LayoutBuilder) pair into one row. The old
      // IntrinsicHeight wrapper measured that LayoutBuilder and threw
      // "LayoutBuilder does not support returning intrinsic dimensions" —
      // and because IndexedStack lays out every tab, it broke the whole
      // page, not just this one. A breakdown pair never tripped it
      // (breakdown has no LayoutBuilder), which is why it went uncaught.
      await pump(
        tester,
        _loaded([
          _barsMetric(key: 'promotions_trend', name: 'Promotions'),
          _barsMetric(
            key: 'redemptions_trend',
            name: 'Redemptions',
            order: 20,
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Promotions'), findsOneWidget);
      expect(find.text('Redemptions'), findsOneWidget);
    });

    testWidgets('tapping a tab switches the body', (tester) async {
      await pump(tester, _loaded(_oneMetricPerTab()));
      expect(tabIndex(tester), 0);

      await tester.tap(find.text('Revenue'));
      await tester.pump();
      expect(tabIndex(tester), 2);

      await tester.tap(find.text('Retention'));
      await tester.pump();
      expect(tabIndex(tester), 5);
    });
  });

  group('deep links', () {
    test('every tab route is addressable, in tab order', () {
      expect(kGrowthTabRoutes, [
        AppRoutes.growth,
        AppRoutes.growthMembers,
        AppRoutes.growthRevenue,
        AppRoutes.growthAttendance,
        AppRoutes.growthTrial,
        AppRoutes.growthRetention,
      ]);
      expect(kGrowthTabRoutes.indexOf(AppRoutes.growthAttendance), 3);
    });

    testWidgets('an initial tab index opens that tab', (tester) async {
      await pump(tester, _loaded(_oneMetricPerTab()), initialTab: 3);
      expect(tabIndex(tester), 3);
    });

    testWidgets('an out-of-range initial tab falls back to the last tab',
        (tester) async {
      await pump(tester, _loaded(_oneMetricPerTab()), initialTab: 99);
      expect(tabIndex(tester), 5);
    });
  });

  group('page states', () {
    testWidgets('"not computed yet" explains, and offers NO retry',
        (tester) async {
      await pump(
        tester,
        const GrowthState(status: GrowthStatus.loaded),
      );
      expect(find.text('Your metrics are still being built'), findsOneWidget);
      // Retrying changes nothing — the sweep runs on the backend's clock.
      expect(find.byType(AppOutlineButton), findsNothing);
      expect(find.byType(IndexedStack), findsNothing);
    });

    testWidgets('an error retries through the load event', (tester) async {
      await pump(
        tester,
        const GrowthState(
          status: GrowthStatus.error,
          error: 'Network unreachable.',
        ),
      );
      expect(find.text("Couldn't load your metrics"), findsOneWidget);
      expect(find.text('Network unreachable.'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      verify(() => bloc.add(const GrowthLoadRequested())).called(1);
    });

    testWidgets('loading shows a spinner and no tab bodies', (tester) async {
      await pump(tester, const GrowthState(status: GrowthStatus.loading));
      expect(find.byType(IndexedStack), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
    });
  });

  group('range pill', () {
    testWidgets('trims the series handed to the renderer', (tester) async {
      await pump(tester, _loaded([_lineMetric()]));

      LineData renderedLine() => tester
          .widget<GrowthMetricView>(
            find.descendant(
              of: find.byType(OverviewTab),
              matching: find.byType(GrowthMetricView),
            ),
          )
          .metric
          .data as LineData;

      expect(renderedLine().series.first.points, hasLength(24));

      await tester.tap(find.text('3M'));
      await tester.pump();
      expect(renderedLine().series.first.points, hasLength(4));

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(renderedLine().series.first.points, hasLength(24));
    });

    testWidgets('is hidden on a tab with no time series', (tester) async {
      await pump(
        tester,
        _loaded([_breakdown(GrowthCategory.overview, 'Overview stat')]),
      );
      expect(find.text('3M'), findsNothing);
    });
  });

  group('class filter', () {
    List<ClassSeries> boxingOnly() => [
          ClassSeries(
            classId: 'class-1',
            className: 'Boxing',
            series: [
              MetricSeries(
                key: 'total',
                label: 'Total',
                points: _monthlyPoints(),
              ),
            ],
          ),
        ];

    testWidgets('passes the selected classId into the renderer',
        (tester) async {
      await pump(
        tester,
        _loaded([
          _lineMetric(
            category: GrowthCategory.attendance,
            name: 'Check-ins',
            byClass: boxingOnly(),
          ),
        ]),
        initialTab: 3,
      );

      String? renderedClassId() => tester
          .widget<GrowthMetricView>(
            find.descendant(
              of: find.byType(AttendanceTab),
              matching: find.byType(GrowthMetricView),
            ),
          )
          .classId;

      expect(find.text('All classes'), findsOneWidget);
      expect(renderedClassId(), isNull);

      await tester.tap(find.text('Boxing'));
      await tester.pump();
      expect(renderedClassId(), 'class-1');

      await tester.tap(find.text('All classes'));
      await tester.pump();
      expect(renderedClassId(), isNull);
    });

    testWidgets('shows no chips when no metric carries by_class',
        (tester) async {
      await pump(
        tester,
        _loaded([
          _lineMetric(category: GrowthCategory.attendance, name: 'Check-ins'),
        ]),
        initialTab: 3,
      );
      expect(find.text('All classes'), findsNothing);
    });
  });
}
