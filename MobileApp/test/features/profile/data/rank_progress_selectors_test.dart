import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/features/profile/data/models/rank_progress_point.dart';
import 'package:mobile_app/features/profile/data/rank_progress_selectors.dart';

RankProgressPoint _p(String date, int into, {int needed = 10}) =>
    RankProgressPoint(date: date, classesIntoRank: into, classesNeeded: needed);

void main() {
  group('plottableSeries', () {
    test('normalizes classes-into-rank against the per-step threshold', () {
      final series = plottableSeries([
        _p('2026-07-01', 0),
        _p('2026-07-05', 4),
        _p('2026-07-09', 10),
      ]);
      expect(series, [0.0, 0.4, 1.0]);
    });

    test('reflects the reset-to-0 at a rank change (a sawtooth)', () {
      // ...8, 9, 10 (promotion), then the counter resets to 0 and climbs again.
      final series = plottableSeries([
        _p('2026-07-01', 8),
        _p('2026-07-03', 9),
        _p('2026-07-05', 10),
        _p('2026-07-06', 0),
        _p('2026-07-08', 1),
      ]);
      expect(series, [0.8, 0.9, 1.0, 0.0, 0.1]);
    });

    test('caps a point that exceeds its threshold at 1.0', () {
      final series = plottableSeries([_p('2026-07-01', 12, needed: 10)]);
      expect(series, [1.0]);
    });

    test('maps a non-positive threshold to 0 (never divides by zero)', () {
      final series = plottableSeries([_p('2026-07-01', 3, needed: 0)]);
      expect(series, [0.0]);
    });

    test('is empty for no points', () {
      expect(plottableSeries(const []), isEmpty);
    });
  });

  group('windowPoints', () {
    final points = [
      _p('2026-06-01', 1),
      _p('2026-07-01', 3),
      _p('2026-07-18', 5),
      _p('2026-07-20', 6),
    ];

    test('ALL returns the whole series unchanged', () {
      expect(windowPoints(points, RankTimeframe.all), points);
    });

    test('a week window keeps only points within 7 days of the latest', () {
      // Anchor = 2026-07-20; cutoff = 2026-07-13 → keeps 07-18 and 07-20.
      final windowed = windowPoints(points, RankTimeframe.week);
      expect(windowed.map((p) => p.date), ['2026-07-18', '2026-07-20']);
    });

    test('a month window keeps points within 30 days of the latest', () {
      // Cutoff = 2026-06-20 → drops 06-01, keeps the other three.
      final windowed = windowPoints(points, RankTimeframe.month);
      expect(
        windowed.map((p) => p.date),
        ['2026-07-01', '2026-07-18', '2026-07-20'],
      );
    });

    test('keeps a point whose date cannot be parsed (never hides data)', () {
      final withBadDate = [_p('not-a-date', 2), _p('2026-07-20', 6)];
      final windowed = windowPoints(withBadDate, RankTimeframe.week);
      expect(windowed.map((p) => p.date), ['not-a-date', '2026-07-20']);
    });

    test('returns the series unchanged when it is empty', () {
      expect(windowPoints(const [], RankTimeframe.week), isEmpty);
    });
  });
}
