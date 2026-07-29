import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/profile/data/models/billing_personal_info.dart';
import 'package:mobile_app/features/profile/data/models/billing_rank.dart';
import 'package:mobile_app/features/profile/data/models/billing_retention.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/celebration_stats_builder.dart';

MemberProfile _profile({
  int streak = 3,
  int points = 1250,
  BillingRank? rank,
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
      ),
      rank: rank,
    );

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
