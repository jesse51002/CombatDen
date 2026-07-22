import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/member_list_cells.dart';

import 'growth_renderer_fixtures.dart';

void main() {
  const columns = [
    MemberListColumn(
      key: 'name',
      label: 'Member',
      type: MemberListColumnType.text,
    ),
    MemberListColumn(
      key: 'visits',
      label: 'Visits',
      type: MemberListColumnType.number,
    ),
    MemberListColumn(
      key: 'owed',
      label: 'Owed',
      type: MemberListColumnType.cents,
    ),
    MemberListColumn(
      key: 'last_seen',
      label: 'Last seen',
      type: MemberListColumnType.date,
    ),
  ];

  testWidgets('each column type formats its own cell', (tester) async {
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
    await tester.pumpWidget(
      host(
        GrowthMetricView(
          metric: memberListMetric(
            columns: columns,
            rows: [
              MemberListRow(
                memberId: 'm-1',
                cells: [
                  'Ana Reyes',
                  1284.0,
                  4500.0,
                  threeDaysAgo.toIso8601String(),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('1,284'), findsOneWidget);
    expect(find.text(r'$45'), findsOneWidget);
    expect(find.text('3 days ago'), findsOneWidget);
  });

  testWidgets('a null cell renders an em-dash, never "null" or 0',
      (tester) async {
    await tester.pumpWidget(
      host(
        GrowthMetricView(
          metric: memberListMetric(
            columns: columns,
            rows: const [
              MemberListRow(
                memberId: 'm-2',
                cells: ['Sam Ito', null, null, null],
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(kEmptyCell), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
    expect(find.text('null'), findsNothing);
    expect(find.text(r'$0'), findsNothing);
  });

  testWidgets('a short row does not throw on the missing cells',
      (tester) async {
    await tester.pumpWidget(
      host(
        GrowthMetricView(
          metric: memberListMetric(
            columns: columns,
            rows: const [
              MemberListRow(memberId: 'm-3', cells: ['Only a name']),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Only a name'), findsOneWidget);
  });

  testWidgets('caps at ten rows', (tester) async {
    await tester.pumpWidget(
      host(
        GrowthMetricView(
          metric: memberListMetric(
            columns: const [
              MemberListColumn(
                key: 'name',
                label: 'Member',
                type: MemberListColumnType.text,
              ),
            ],
            rows: [
              for (var i = 0; i < 14; i++)
                MemberListRow(memberId: 'm-$i', cells: ['Member $i']),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Member 9'), findsOneWidget);
    expect(find.text('Member 10'), findsNothing);
  });

  group('relativeDay', () {
    final now = DateTime(2026, 7, 20);
    test('names today and yesterday', () {
      expect(relativeDay(DateTime(2026, 7, 20, 9), now: now), 'Today');
      expect(relativeDay(DateTime(2026, 7, 19), now: now), 'Yesterday');
    });

    test('counts days either side', () {
      expect(relativeDay(DateTime(2026, 7, 14), now: now), '6 days ago');
      expect(relativeDay(DateTime(2026, 7, 25), now: now), 'in 5 days');
    });
  });
}
