import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/growth/bloc/growth_bloc.dart';
import 'package:crm/features/growth/bloc/growth_event.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/data/repositories/growth_repository.dart';
import 'package:crm/core/auth/employee_role.dart';

class _MockGrowthRepository extends Mock implements GrowthRepository {}

void main() {
  late _MockGrowthRepository repository;
  const gymId = 'gym-1';
  const computedAt = '2026-07-21T18:00:00Z';

  setUp(() {
    repository = _MockGrowthRepository();
    selectedGym.setActiveGym(
      gymId: gymId,
      displayName: 'Test Gym',
      role: EmployeeRole.owner,
      timezone: 'America/Chicago',
      logoUrl: null,
    );
  });

  tearDown(selectedGym.reset);

  Map<String, dynamic> metric({
    required String key,
    required String type,
    required Object? data,
    List<String> categories = const ['overview'],
    int order = 10,
  }) => {
        'key': key,
        'name': 'Metric $key',
        'categories': categories,
        'type': type,
        'order': order,
        'computed_at': computedAt,
        'data': data,
      };

  final kpiData = {
    'tiles': [
      {
        'key': 'active',
        'label': 'Active members',
        'value': 42,
        'unit': 'count',
        'delta_pct': 12.5,
      },
    ],
  };

  final lineData = {
    'unit': 'count',
    'granularity': 'week',
    'series': [
      {
        'key': 'joins',
        'label': 'Joins',
        'points': [
          {'date': '2026-07-01', 'value': 3},
        ],
      },
    ],
  };

  final donutData = {
    'donuts': [
      {'key': 'conv', 'label': 'Trial conversion', 'pct': 61.0},
    ],
  };

  /// Stubs the repository to return the REAL parse of [response], so these
  /// tests exercise the skip-on-parse-failure path, not a hand-built page.
  void stubResponse(Map<String, dynamic> response) {
    when(() => repository.getGrowth(any()))
        .thenAnswer((_) async => GrowthPage.fromJson(response));
  }

  List<String> keysOf(GrowthState s) =>
      s.metrics.map((m) => m.key).toList(growable: false);

  group('GrowthBloc', () {
    blocTest<GrowthBloc, GrowthState>(
      'loads the gym metrics (loading -> loaded)',
      setUp: () => stubResponse({
        'computed_at': computedAt,
        'metrics': [
          metric(key: 'kpis', type: 'kpi_group', data: kpiData),
          metric(key: 'joins', type: 'line', data: lineData, order: 20),
        ],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loaded)
            .having(keysOf, 'metrics', ['kpis', 'joins'])
            .having((s) => s.metrics.first.data, 'kpi payload',
                isA<KpiGroupData>())
            .having((s) => s.metrics.last.data, 'line payload',
                isA<LineData>())
            .having((s) => s.computedAt, 'computedAt',
                DateTime.parse(computedAt))
            .having((s) => s.error, 'error', isNull)
            .having((s) => s.isNotComputedYet, 'isNotComputedYet', false),
      ],
      verify: (_) => verify(() => repository.getGrowth(gymId)).called(1),
    );

    blocTest<GrowthBloc, GrowthState>(
      'surfaces a user-facing message when the read fails',
      setUp: () {
        when(() => repository.getGrowth(any())).thenThrow(
          const ServerException(
            'Request failed',
            statusCode: 500,
            detail: 'Failed to retrieve growth metrics',
          ),
        );
      },
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.error)
            .having(
              (s) => s.error,
              'error',
              'Failed to retrieve growth metrics',
            )
            .having((s) => s.isNotComputedYet, 'isNotComputedYet', false),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'drops a metric whose payload does not fit its type, keeping its '
      'neighbours',
      setUp: () => stubResponse({
        'computed_at': computedAt,
        'metrics': [
          metric(key: 'before', type: 'kpi_group', data: kpiData),
          // `line` payload with no `series` array — unparseable.
          metric(
            key: 'broken',
            type: 'line',
            data: const {'unit': 'count', 'granularity': 'week'},
          ),
          metric(key: 'after', type: 'donut_pair', data: donutData),
        ],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loaded)
            .having(keysOf, 'metrics', ['before', 'after']),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'drops a metric with an unrecognised type, keeping its neighbours',
      setUp: () => stubResponse({
        'computed_at': computedAt,
        'metrics': [
          metric(key: 'before', type: 'kpi_group', data: kpiData),
          metric(key: 'sunburst', type: 'sunburst', data: const {'x': 1}),
          metric(key: 'after', type: 'donut_pair', data: donutData),
        ],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loaded)
            .having(keysOf, 'metrics', ['before', 'after']),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'an empty page with a null computed_at reads as "not computed yet", '
      'not as an error',
      setUp: () => stubResponse({
        'computed_at': null,
        'metrics': const <dynamic>[],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loaded)
            .having((s) => s.metrics, 'metrics', isEmpty)
            .having((s) => s.computedAt, 'computedAt', isNull)
            .having((s) => s.error, 'error', isNull)
            .having((s) => s.isNotComputedYet, 'isNotComputedYet', true),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'metricsIn filters by category and orders by the registry order',
      setUp: () => stubResponse({
        'computed_at': computedAt,
        'metrics': [
          metric(
            key: 'late',
            type: 'kpi_group',
            data: kpiData,
            categories: const ['overview', 'members'],
            order: 90,
          ),
          metric(
            key: 'revenue-only',
            type: 'donut_pair',
            data: donutData,
            categories: const ['revenue'],
            order: 10,
          ),
          metric(
            key: 'early',
            type: 'line',
            data: lineData,
            categories: const ['members'],
            order: 20,
          ),
        ],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having(
              (s) => s
                  .metricsIn(GrowthCategory.members)
                  .map((m) => m.key)
                  .toList(),
              'members tab',
              ['early', 'late'],
            )
            .having(
              (s) => s
                  .metricsIn(GrowthCategory.revenue)
                  .map((m) => m.key)
                  .toList(),
              'revenue tab',
              ['revenue-only'],
            )
            .having(
              (s) => s.metricsIn(GrowthCategory.attendance),
              'attendance tab',
              isEmpty,
            ),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'keeps unknown heatmap cells null (never coerced to zero)',
      setUp: () => stubResponse({
        'computed_at': computedAt,
        'metrics': [
          metric(
            key: 'cohorts',
            type: 'heatmap',
            data: const {
              'unit': 'percent',
              'rows': ['Jan', 'Feb'],
              'cols': ['M1', 'M2'],
              'cells': [
                [100, 80],
                [100, null],
              ],
            },
          ),
        ],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>().having(
          (s) => (s.metrics.single.data as HeatmapData).cells,
          'cells',
          const [
            [100.0, 80.0],
            [100.0, null],
          ],
        ),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'normalises member_list number cells to double and keeps nulls',
      setUp: () => stubResponse({
        'computed_at': computedAt,
        'metrics': [
          metric(
            key: 'at-risk',
            type: 'member_list',
            data: const {
              'columns': [
                {'key': 'name', 'label': 'Member', 'type': 'text'},
                {'key': 'spend', 'label': 'Spend', 'type': 'cents'},
                {'key': 'last', 'label': 'Last class', 'type': 'date'},
              ],
              'rows': [
                {
                  'member_id': 'm-1',
                  'cells': ['Ada', 12000, null],
                },
              ],
            },
          ),
        ],
      }),
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>().having(
          (s) => (s.metrics.single.data as MemberListData).rows.single.cells,
          'cells',
          const ['Ada', 12000.0, null],
        ),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'a failed refresh keeps the last loaded page (no error state)',
      setUp: () {
        var calls = 0;
        when(() => repository.getGrowth(any())).thenAnswer((_) async {
          calls++;
          if (calls > 1) throw const NetworkException('offline');
          return GrowthPage.fromJson({
            'computed_at': computedAt,
            'metrics': [
              metric(key: 'kpis', type: 'kpi_group', data: kpiData),
            ],
          });
        });
      },
      build: () => GrowthBloc(repository: repository),
      act: (bloc) async {
        bloc.add(const GrowthLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const GrowthRefreshRequested());
      },
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loading),
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.loaded)
            .having(keysOf, 'metrics', ['kpis']),
      ],
    );

    blocTest<GrowthBloc, GrowthState>(
      'errors instead of hanging when no gym is selected',
      setUp: selectedGym.reset,
      build: () => GrowthBloc(repository: repository),
      act: (bloc) => bloc.add(const GrowthLoadRequested()),
      expect: () => [
        isA<GrowthState>()
            .having((s) => s.status, 'status', GrowthStatus.error)
            .having((s) => s.error, 'error', 'No gym selected.'),
      ],
      verify: (_) => verifyNever(() => repository.getGrowth(any())),
    );
  });
}
