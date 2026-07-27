import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_bloc.dart';
import 'package:mobile_app/features/profile/bloc/member_profile_state.dart';
import 'package:mobile_app/features/profile/presentation/widgets/level_up_videos/level_up_videos_section.dart';
import 'package:mobile_app/features/profile/presentation/widgets/profile_streak_hero.dart';
import 'package:mobile_app/features/profile/presentation/widgets/streak_week/profile_streak_week.dart';
import 'package:mobile_app/features/profile/presentation/widgets/streak_week/streak_facts.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';

/// How long the week strip's badge cascade runs before the facts follow: one
/// [CelebrationTimings.badgeStagger] per day. Keeps the whole entrance inside
/// the ~900ms budget (620ms sparkles ‖ 490ms + 260ms reveal). Top-level
/// `final` because `Duration`'s `*` isn't a const operator.
final Duration _kFactsDelay = CelebrationTimings.badgeStagger * 7;

/// The profile page for a gym that runs NO rank ladder: the streak hero, this
/// week's day strip, and two plain facts — one vertically-centred block.
///
/// Motion is one-shot and short: the hero's own 620ms sparkle scatter, the
/// strip's 70ms-per-badge cascade, and one [StaggeredReveal] on the facts. The
/// celebration card's ~3s orbit intro and its 1400ms count-up are deliberately
/// NOT carried over — a tab you return to every day can't re-earn its entrance.
class RanklessProfileBody extends StatelessWidget {
  const RanklessProfileBody({super.key, required this.bottomPadding});

  /// Clears the persistent bottom nav.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: const [
          ProfileStreakHero(allowZeroState: true),
          ProfileStreakWeek(),
          _StreakClose(),
          LevelUpVideosSection(leadingDivider: true),
        ],
      ),
    );
  }
}

/// What sits under the week strip: the two facts once the member has a streak,
/// or — at zero, the emptiest state there is — the one action that starts one.
class _StreakClose extends StatelessWidget {
  const _StreakClose();

  /// Zero means a LOADED profile with no streak. An unloaded (or failed)
  /// profile is not zero — telling a member with a twelve-week streak to
  /// "start" one because their fetch hasn't landed is worse than a dash.
  static bool _isZero(MemberProfileState s) {
    final retention = s.profile?.retention;
    return retention != null && retention.classStreakWeeks == 0;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberProfileBloc, MemberProfileState>(
      // Only the zero/non-zero flip changes this slot — a silent refresh must
      // not re-fire the facts' reveal.
      buildWhen: (p, c) => _isZero(p) != _isZero(c),
      builder: (context, state) {
        if (_isZero(state)) {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.paddingBig,
            ),
            child: AppPrimaryButton(
              text: 'Book a class',
              fullWidth: true,
              borderRadius: DesignConstants.radiusBig,
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed(AppRoutes.home),
            ),
          );
        }
        return StaggeredReveal(
          delay: _kFactsDelay,
          child: const StreakFacts(),
        );
      },
    );
  }
}
