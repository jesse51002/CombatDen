import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/shared/widgets/sparkle_hero/sparkle_hero.dart';

/// The "YOU HAVE A / N WEEK / STREAK" hero, its week count read LIVE from the
/// shared [MemberProfileBloc] retention (never mock). Rebuilds only when the
/// streak changes so the sparkle animation isn't restarted by unrelated
/// profile updates.
class ProfileStreakHero extends StatelessWidget {
  const ProfileStreakHero({super.key, this.allowZeroState = false});

  /// Opt in to the ZERO-streak copy ("START YOUR / STREAK / BOOK A CLASS",
  /// sparkles suppressed). Only the rank-less profile — where this hero is the
  /// whole screen — turns it on; a rank-enabled profile keeps the count hero
  /// verbatim, because it has a rank block carrying the page either way.
  final bool allowZeroState;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      buildWhen: (p, c) =>
          p.profile?.retention.classStreakWeeks !=
          c.profile?.retention.classStreakWeeks,
      builder: (context, state) {
        final loaded = state.profile?.retention;
        final weeks = loaded?.classStreakWeeks ?? 0;
        // "0 WEEK STREAK" celebrates nothing — name the goal instead, and drop
        // the sparkles, which are the earned part. Only on a LOADED profile:
        // an unresolved fetch must not tell a member with a streak to start
        // one.
        if (allowZeroState && loaded != null && weeks == 0) {
          return SparkleHero(
            top: 'START YOUR',
            accent: 'STREAK',
            bottom: 'BOOK A CLASS',
            showSparkles: false,
          );
        }
        return SparkleHero(
          top: 'YOU HAVE A',
          accent: '$weeks WEEK',
          bottom: 'STREAK',
        );
      },
    );
  }
}
