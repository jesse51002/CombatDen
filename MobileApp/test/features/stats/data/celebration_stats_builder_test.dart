import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';

MemberProfile _profile({
  int streak = 3,
  int points = 1250,
  BillingRank? rank,
  List<int> weekdays = const [],
}) =>
    MemberProfile(
      memberId: 'm1',
      gymId: 'g1',
      firstName: 'Jane',
      lastName: 'Doe',
      personalInfo: const BillingPersonalInfo(),
      retention: BillingRetention(
        classStreakWeeks: streak,
        pointsBalance: points,
        videosWatched: 0,
        currentWeekAttendedWeekdays: weekdays,
      ),
      rank: rank,
    );

/// The tile carrying [label], so an assertion names what it is checking rather
/// than an index that a reordering would silently repoint.
MockWinTile _tile(MockWinsStats stats, String label) =>
    stats.tiles.firstWhere((t) => t.label == label);

void main() {
  group('buildStreakStats', () {
    test('maps live streak weeks, the +points subtitle, and the day strip', () {
      final stats = buildStreakStats(
        _profile(streak: 5),
        const CelebrationData(
          pointsWorth: 120,
          completedWeekdayIndices: [1, 4],
        ),
      );
      expect(stats.weekCount, 5);
      expect(stats.subtitle, '+120 points');
      expect(stats.weekDays.map((d) => d.label).toList(),
          ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
      expect(
        [for (var i = 0; i < 7; i++) stats.weekDays[i].completed],
        [false, true, false, false, true, false, false],
      );
    });

    test('null profile falls back to a zero streak', () {
      final stats = buildStreakStats(
        null,
        const CelebrationData(pointsWorth: 0, completedWeekdayIndices: [0]),
      );
      expect(stats.weekCount, 0);
      expect(stats.subtitle, '+0 points');
    });

    test('null day strip highlights only the attended day', () {
      final stats = buildStreakStats(
        _profile(),
        CelebrationData(
          pointsWorth: 50,
          occurredAt: DateTime.utc(2026, 7, 23), // Thursday -> index 4
        ),
      );
      final completed = [
        for (var i = 0; i < 7; i++) if (stats.weekDays[i].completed) i,
      ];
      expect(completed, [4]);
    });
  });

  group('buildPointsStats', () {
    test('gains the class worth, totals the live balance', () {
      final stats = buildPointsStats(
        _profile(points: 3400),
        const CelebrationData(pointsWorth: 160),
      );
      expect(stats.gained, 160);
      expect(stats.totalPoints, 3400);
    });

    test('null profile totals zero', () {
      final stats =
          buildPointsStats(null, const CelebrationData(pointsWorth: 10));
      expect(stats.gained, 10);
      expect(stats.totalPoints, 0);
    });
  });

  group('buildWinsStats', () {
    test('derives all three tiles from live values', () {
      final stats = buildWinsStats(
        _profile(streak: 4, weekdays: [1, 3, 5]),
        const CelebrationData(pointsWorth: 160),
      );

      expect(stats.tiles.length, 3);
      // Classes this week is the LENGTH of the profile's own weekday list —
      // the same list the profile's week strip draws. Fetching class history
      // for a number the profile read already carries is the bug this guards.
      expect(_tile(stats, 'Classes this week').value, '3');
      expect(_tile(stats, 'Points').value, '+160');
      expect(_tile(stats, 'Streak').value, '4 weeks');
    });

    test('keeps the demo icon association, and adds nothing new', () {
      final stats = buildWinsStats(
        _profile(),
        const CelebrationData(pointsWorth: 10),
      );
      expect(_tile(stats, 'Streak').iconName, 'star');
      expect(_tile(stats, 'Points').iconName, 'gift');
      expect(_tile(stats, 'Classes this week').iconName, 'award');
      // The widget's mapper knows exactly these three; a fourth name would
      // silently render the help glyph.
      expect(
        stats.tiles.map((t) => t.iconName),
        everyElement(isIn(['star', 'award', 'gift'])),
      );
    });

    test('a one-week streak is singular', () {
      final stats = buildWinsStats(
        _profile(streak: 1),
        const CelebrationData(pointsWorth: 0),
      );
      expect(_tile(stats, 'Streak').value, '1 week');
    });

    test('a broken streak is plural, not "0 week"', () {
      final stats = buildWinsStats(
        _profile(streak: 0),
        const CelebrationData(pointsWorth: 0),
      );
      expect(_tile(stats, 'Streak').value, '0 weeks');
    });

    test('an empty week is zero classes, not a missing tile', () {
      final stats = buildWinsStats(
        _profile(weekdays: const []),
        const CelebrationData(pointsWorth: 25),
      );
      expect(_tile(stats, 'Classes this week').value, '0');
    });

    test('a null profile degrades to zeros, keeping the class points', () {
      final stats = buildWinsStats(null, const CelebrationData(pointsWorth: 75));
      expect(_tile(stats, 'Classes this week').value, '0');
      expect(_tile(stats, 'Streak').value, '0 weeks');
      // The one value that does NOT come from the profile survives it.
      expect(_tile(stats, 'Points').value, '+75');
    });

    test('carries the themed fallbacks the card renders under its slots', () {
      final stats = buildWinsStats(
        _profile(),
        const CelebrationData(pointsWorth: 5),
      );
      expect(stats.title, isNotEmpty);
      expect(stats.subtitle, isNotEmpty);
      expect(stats.heroAsset, 'stat_wins_trophy.png');
    });
  });

  group('buildRankStats', () {
    test('maps a live rank to the card view-model', () {
      final stats = buildRankStats(_profile(
        rank: const BillingRank(
          rankId: 'r1',
          name: 'Blue Belt',
          subLabel: 'Stripe II',
          classesToNextMajor: 50,
          classesTillNextStep: 50,
          classesSinceRank: 28,
        ),
      ));
      expect(stats, isNotNull);
      expect(stats!.rankTitle, 'Blue Belt');
      expect(stats.rankSubtitle, 'Stripe II');
      expect(stats.classesAttended, 28);
      expect(stats.classesRequired, 50);
    });

    test("carries the member's OWN belt art through to the card", () {
      final stats = buildRankStats(_profile(
        rank: const BillingRank(
          rankId: 'r1',
          name: 'Purple Belt',
          classesToNextMajor: 60,
          classesTillNextStep: 30,
          imageUrl: 'https://cdn.test/purple.png',
        ),
      ));
      // Dropping this is what made the card celebrate the THEME's belt at
      // every gym that runs its own ranks.
      expect(stats!.rankImageUrl, 'https://cdn.test/purple.png');
      // The bundled floor under the themed slot survives alongside it.
      expect(stats.beltAsset, 'stat_rank_belt.png');
    });

    test('leaves the belt art null when the rank carries no image', () {
      final stats = buildRankStats(_profile(
        rank: const BillingRank(
          rankId: 'r1',
          name: 'White Belt',
          classesToNextMajor: 40,
          classesTillNextStep: 40,
        ),
      ));
      expect(stats!.rankImageUrl, isNull);
    });

    test('is null when the member holds no rank', () {
      expect(buildRankStats(_profile()), isNull);
      expect(buildRankStats(null), isNull);
    });
  });
}
