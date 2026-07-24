import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/features/schedule/presentation/widgets/list/schedule_day_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The schedule board is the ONE surface that asks the backend for paused
/// occurrences (`includeInactive: true`), so it is the only place a card can
/// belong to a paused class — and staff must be able to see which. These
/// cover the flag's path from the wire model to the rendered badge.
EffectiveClassInstance _instance({required bool isActive}) =>
    EffectiveClassInstance(
      classId: 'class-1',
      gymId: 'gym-1',
      className: 'Competition Team',
      classDate: DateTime(2026, 6, 3),
      originalDate: DateTime(2026, 6, 3),
      originalTime: '09:00:00',
      occurredAt: DateTime.utc(2026, 6, 3, 14),
      resolvedClassTime: '09:00:00',
      resolvedDurationMinutes: 60,
      pointsWorth: 10,
      isActive: isActive,
      isCancelled: false,
      hasInstanceException: false,
      hasRangeException: false,
    );

Widget _column(ScheduleClassEntry entry, {VoidCallback? onTap}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScheduleDayColumn(
            group: ScheduleDayGroup(
              dayLabel: 'Wed, Jun 3',
              classes: [entry],
            ),
            onClassTap: (_) => onTap?.call(),
          ),
        ),
      ),
    );

void main() {
  test('fromInstance carries isActive through to the rendered entry', () {
    expect(
      ScheduleClassEntry.fromInstance(_instance(isActive: true)).isActive,
      isTrue,
    );
    expect(
      ScheduleClassEntry.fromInstance(_instance(isActive: false)).isActive,
      isFalse,
    );
  });

  test('isActive defaults to true when the backend omits it', () {
    // Fail OPEN on a backend older than this build: a missing flag renders
    // the class normally rather than badging every card "Paused".
    final json = <String, dynamic>{
      'class_id': 'class-1',
      'gym_id': 'gym-1',
      'class_name': 'Boxing',
      'class_date': '2026-06-03',
      'original_date': '2026-06-03',
      'original_time': '09:00:00',
      'occurred_at': '2026-06-03T14:00:00Z',
      'resolved_class_time': '09:00:00',
      'resolved_duration_minutes': 60,
      'points_worth': 10,
      'is_cancelled': false,
      'has_instance_exception': false,
      'has_range_exception': false,
    };

    expect(EffectiveClassInstance.fromJson(json).isActive, isTrue);
  });

  testWidgets('a paused occurrence renders a Paused badge', (tester) async {
    final entry =
        ScheduleClassEntry.fromInstance(_instance(isActive: false));

    await tester.pumpWidget(_column(entry));

    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('a live occurrence renders no Paused badge', (tester) async {
    final entry = ScheduleClassEntry.fromInstance(_instance(isActive: true));

    await tester.pumpWidget(_column(entry));

    expect(find.text('Paused'), findsNothing);
  });

  testWidgets('a paused card is still tappable (it opens the class editor)',
      (tester) async {
    var taps = 0;
    final entry =
        ScheduleClassEntry.fromInstance(_instance(isActive: false));

    await tester.pumpWidget(_column(entry, onTap: () => taps++));
    await tester.tap(find.text('Competition Team'));

    expect(taps, 1);
  });
}
