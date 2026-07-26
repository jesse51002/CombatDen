import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/data/streak_week_days.dart';

/// Builds the celebration cards' view-models from LIVE data — the shared
/// [MemberProfile] (streak / points / rank) plus the triggering occurrence's
/// [CelebrationData] (points earned, this-week day strip).
///
/// The [MockStreakStats] / [MockPointsStats] / [MockRankStats] carrier types
/// are reused verbatim so the existing celebration widgets (and the capture
/// harness that renders them) render unchanged — this is a data swap, not a
/// re-layout. This is the one place that constructs them from live values; the
/// screens call these builders instead of importing the demo constants.

MockStreakStats buildStreakStats(MemberProfile? profile, CelebrationData data) {
  final completed = (data.completedWeekdayIndices ??
          <int>[if (data.occurredAt != null) data.occurredAt!.weekday % 7])
      .toSet();
  return MockStreakStats(
    weekCount: profile?.retention.classStreakWeeks ?? 0,
    subtitle: '+${data.pointsWorth} points',
    weekDays: streakWeekDays(completed),
  );
}

MockPointsStats buildPointsStats(MemberProfile? profile, CelebrationData data) {
  return MockPointsStats(
    gained: data.pointsWorth,
    totalPoints: profile?.retention.pointsBalance ?? 0,
  );
}

/// The rank card's view-model, or null when the member holds no rank (ranks
/// disabled / unranked) — the rank card is then skipped by the screen.
MockRankStats? buildRankStats(MemberProfile? profile) {
  final rank = profile?.rank;
  if (rank == null) return null;
  return MockRankStats(
    rankTitle: rank.name,
    rankSubtitle: rank.subLabel ?? '',
    beltAsset: 'stat_rank_belt.png',
    nextTierLabel: '',
    classesAttended: rank.classesSinceRank,
    classesRequired: rank.classesTillNextStep,
  );
}
