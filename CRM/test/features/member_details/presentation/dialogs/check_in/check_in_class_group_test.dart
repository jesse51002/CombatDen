import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_class_group.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

EffectiveClassInstance _instance({
  required String classId,
  required String className,
  required DateTime classDate,
  String? imageUrl,
}) {
  return EffectiveClassInstance(
    classId: classId,
    gymId: 'gym-1',
    className: className,
    classDate: classDate,
    originalDate: classDate,
    originalTime: '18:00:00',
    occurredAt: classDate,
    resolvedClassTime: '18:00:00',
    resolvedDurationMinutes: 60,
    imageUrl: imageUrl,
    pointsWorth: 10,
    isCancelled: false,
    hasInstanceException: false,
    hasRangeException: false,
  );
}

void main() {
  group('groupInstancesByClass', () {
    test('groups occurrences by classId, preserving first-seen order', () {
      final boxing1 = _instance(
        classId: 'boxing',
        className: 'Boxing',
        classDate: DateTime(2026, 7, 3),
        imageUrl: 'boxing.png',
      );
      final yoga = _instance(
        classId: 'yoga',
        className: 'Yoga',
        classDate: DateTime(2026, 7, 4),
      );
      final boxing2 = _instance(
        classId: 'boxing',
        className: 'Boxing',
        classDate: DateTime(2026, 7, 10),
      );

      final groups = groupInstancesByClass([boxing1, yoga, boxing2]);

      expect(groups, hasLength(2));
      expect(groups[0].classId, 'boxing');
      expect(groups[0].className, 'Boxing');
      expect(groups[0].imageUrl, 'boxing.png');
      expect(groups[0].occurrences, [boxing1, boxing2]);
      expect(groups[1].classId, 'yoga');
      expect(groups[1].occurrences, [yoga]);
    });

    test('representative is the group\'s first occurrence, honoring the '
        "caller's sort order", () {
      // A most-recent-first (past) list: the representative should be the
      // most recent occurrence, not the earliest.
      final recent = _instance(
        classId: 'boxing',
        className: 'Boxing',
        classDate: DateTime(2026, 6, 30),
      );
      final older = _instance(
        classId: 'boxing',
        className: 'Boxing',
        classDate: DateTime(2026, 6, 20),
      );

      final groups = groupInstancesByClass([recent, older]);

      expect(groups, hasLength(1));
      expect(groups.single.representative, recent);
    });

    test('empty input yields no groups', () {
      expect(groupInstancesByClass(const []), isEmpty);
    });
  });
}
