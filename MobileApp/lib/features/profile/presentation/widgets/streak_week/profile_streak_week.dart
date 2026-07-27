import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/data/models/member_profile.dart';
import 'package:mobile_app/features/stats/data/streak_week_days.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';

/// This week's day strip on the profile — the same [StreakWeekStrip] the
/// post-class celebration shows, fed from the profile's own
/// `retention.current_week_attended_weekdays` (the backend serves it with the
/// profile, so the strip costs no second call).
///
/// Rebuilds ONLY when the completed-day set changes: the strip's badges cascade
/// in on mount, and a silent profile refresh must not restart that cascade.
class ProfileStreakWeek extends StatelessWidget {
  const ProfileStreakWeek({super.key});

  static Set<int> _completed(MemberProfile? profile) =>
      (profile?.retention.currentWeekAttendedWeekdays ?? const <int>[]).toSet();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      buildWhen: (p, c) =>
          !setEquals(_completed(p.profile), _completed(c.profile)),
      builder: (context, state) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingBig),
          child: StreakWeekStrip(days: streakWeekDays(_completed(state.profile))),
        );
      },
    );
  }
}
