import 'package:mobile_app/features/stats/data/mock_stats.dart';

/// Sunday-first day letters for the streak strip.
const List<String> kStreakDayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// The seven Sunday-first [MockStreakDay]s the strip renders, marked complete
/// where [completed] holds that day's Sunday-first index (0 = Sun … 6 = Sat).
///
/// The one builder behind BOTH strips — the post-class celebration card and the
/// profile's week row — so the two can never disagree about which cell a day
/// lands in. The backend's `current_week_attended_weekdays` is already in this
/// indexing; note its WEEK is Monday-anchored (to match `class_streak_weeks`),
/// so a Sunday is the last day of the streak week but is drawn in the FIRST
/// cell. That is deliberate.
List<MockStreakDay> streakWeekDays(Set<int> completed) => [
      for (var i = 0; i < kStreakDayLabels.length; i++)
        MockStreakDay(
          label: kStreakDayLabels[i],
          completed: completed.contains(i),
        ),
    ];
