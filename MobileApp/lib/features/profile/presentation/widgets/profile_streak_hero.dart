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
  const ProfileStreakHero({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      buildWhen: (p, c) =>
          p.profile?.retention.classStreakWeeks !=
          c.profile?.retention.classStreakWeeks,
      builder: (context, state) {
        final weeks = state.profile?.retention.classStreakWeeks ?? 0;
        return SparkleHero(
          top: 'YOU HAVE A',
          accent: '$weeks WEEK',
          bottom: 'STREAK',
        );
      },
    );
  }
}
