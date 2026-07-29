import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/stats/data/celebration_data.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/data/streak_week_days.dart';

/// Builds the celebration cards' view-models from LIVE data — the shared
/// [MemberProfile] (streak / points / rank) plus the triggering occurrence's
/// [CelebrationData] (points earned, this-week day strip).
///
/// The [MockStreakStats] / [MockPointsStats] / [MockRankStats] /
/// [MockWinsStats] carrier types are reused verbatim so the existing
/// celebration widgets (and the capture harness that renders them) render
/// unchanged — this is a data swap, not a re-layout. This is the one place that
/// constructs them from live values; the screens call these builders instead of
/// importing the demo constants.

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

/// The closing Wins card's view-model — the three tiles the flow ends on.
///
/// All three are UNIVERSAL, which is what lets the wins card close every gym's
/// flow with no capability gate: a streak, a count of this week's classes and
/// the points the class was worth exist whether or not the gym runs ranks or
/// rewards. (The demo's "Rank Classes" tile did not — it is replaced here.)
///
/// * **Classes this week** is the LENGTH of the profile's own
///   `current_week_attended_weekdays`, the same list the profile's week strip
///   draws. The profile read already carries it, so the card costs no extra
///   round trip — never fetch class history for this.
/// * **Points** is the attended class's worth, formatted `+N` like the demo so
///   `WinsTile` rolls it up as a count-up.
/// * **Streak** is the member's live week streak, pluralised — a static string,
///   so the tile renders it as text rather than counting it up.
///
/// The title / subtitle / hero asset are the FALLBACKS under
/// `CombatDenSlots.winsTitle` / `winsSubtitle` / `trophyImage`, which is where
/// a tenant overrides this card's copy and art.
MockWinsStats buildWinsStats(MemberProfile? profile, CelebrationData data) {
  final retention = profile?.retention;
  final classesThisWeek = retention?.currentWeekAttendedWeekdays.length ?? 0;
  final streakWeeks = retention?.classStreakWeeks ?? 0;
  return MockWinsStats(
    title: 'Today’s wins',
    subtitle: 'The grind never stops',
    heroAsset: 'stat_wins_trophy.png',
    tiles: [
      MockWinTile(
        iconName: 'award',
        value: '$classesThisWeek',
        label: 'Classes this week',
      ),
      MockWinTile(
        iconName: 'gift',
        value: '+${data.pointsWorth}',
        label: 'Points',
      ),
      MockWinTile(
        iconName: 'star',
        value: '$streakWeeks ${streakWeeks == 1 ? 'week' : 'weeks'}',
        label: 'Streak',
      ),
    ],
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
    // The member's own belt art — the same field the topbar's info bar reads.
    // Without it the card would celebrate the THEME's belt at every gym that
    // runs its own ranks.
    rankImageUrl: rank.imageUrl,
    nextTierLabel: '',
    classesAttended: rank.classesSinceRank,
    classesRequired: rank.classesTillNextStep,
  );
}
