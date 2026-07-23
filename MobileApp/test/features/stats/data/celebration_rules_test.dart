import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/stats/data/celebration_rules.dart';

void main() {
  group('decideCelebration', () {
    final newest = DateTime.utc(2026, 7, 23, 18, 0);

    test('null watermark seeds silently (never replays history)', () {
      expect(
        decideCelebration(lastSeen: null, newestAttended: newest),
        CelebrationDecision.seedSilently,
      );
    });

    test('strictly-newer attendance fires', () {
      expect(
        decideCelebration(
          lastSeen: newest.subtract(const Duration(minutes: 1)),
          newestAttended: newest,
        ),
        CelebrationDecision.fire,
      );
    });

    test('equal attendance does not fire (already seen)', () {
      expect(
        decideCelebration(lastSeen: newest, newestAttended: newest),
        CelebrationDecision.skip,
      );
    });

    test('older attendance does not fire', () {
      expect(
        decideCelebration(
          lastSeen: newest.add(const Duration(hours: 1)),
          newestAttended: newest,
        ),
        CelebrationDecision.skip,
      );
    });
  });

  group('sundayStripIndex', () {
    test('folds Mon..Sun onto a Sunday-first 0..6 strip', () {
      // 2026-07-19 is a Sunday, 2026-07-25 a Saturday.
      expect(sundayStripIndex(DateTime.utc(2026, 7, 19)), 0); // Sun
      expect(sundayStripIndex(DateTime.utc(2026, 7, 20)), 1); // Mon
      expect(sundayStripIndex(DateTime.utc(2026, 7, 23)), 4); // Thu
      expect(sundayStripIndex(DateTime.utc(2026, 7, 25)), 6); // Sat
    });
  });

  group('completedWeekdayIndices', () {
    final anchor = DateTime.utc(2026, 7, 23); // Thursday

    test('always includes the anchor day even with no other rows', () {
      expect(
        completedWeekdayIndices(anchorDate: anchor, attendedDates: const []),
        [4],
      );
    });

    test('collects this week\'s trained weekdays, sorted and de-duped', () {
      final result = completedWeekdayIndices(
        anchorDate: anchor,
        attendedDates: [
          DateTime.utc(2026, 7, 20), // Mon (this week) -> 1
          DateTime.utc(2026, 7, 22), // Wed (this week) -> 3
          DateTime.utc(2026, 7, 23), // Thu (anchor)    -> 4 (dup of anchor)
        ],
      );
      expect(result, [1, 3, 4]);
    });

    test('ignores attendance outside the anchor week', () {
      final result = completedWeekdayIndices(
        anchorDate: anchor,
        attendedDates: [
          DateTime.utc(2026, 7, 16), // Thu of the PREVIOUS week
          DateTime.utc(2026, 7, 27), // Mon of the NEXT week
          DateTime.utc(2026, 7, 21), // Tue (this week) -> 2
        ],
      );
      expect(result, [2, 4]);
    });

    test('includes the Sunday and Saturday edges of the week', () {
      final result = completedWeekdayIndices(
        anchorDate: anchor,
        attendedDates: [
          DateTime.utc(2026, 7, 19), // Sun (week start) -> 0
          DateTime.utc(2026, 7, 25), // Sat (week end)   -> 6
        ],
      );
      expect(result, [0, 4, 6]);
    });
  });
}
