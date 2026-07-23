import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/animation/scale_reveal.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/buttons/app_primary_button.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// The streak icon keeps the topbar's aspect (~22:30); sized up for the hero.
const double _kStreakIconWidth = 48;
const double _kStreakIconHeight = 66;

/// The check-in confirmation content: a quick streak count-up celebrating the
/// member as they walk into class. Reuses [CountUpText] — the count-up segment
/// of the streak celebration — NOT the full `StreakBody` (whose ring/orbit
/// intro is too slow for a walk-in). Tap anywhere or press Done to dismiss.
class CheckinConfirmBody extends StatelessWidget {
  const CheckinConfirmBody({
    super.key,
    required this.className,
    required this.pointsWorth,
    required this.streakWeeks,
    required this.onDone,
  });

  final String className;
  final int pointsWorth;
  final int streakWeeks;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // Short, staggered assembly — the icon pops, the copy and count-up follow,
    // the reward and Done settle in — so the confirm feels earned without ever
    // making a member walking into class wait.
    const step = CelebrationTimings.revealStagger;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            ScaleReveal(
              startScale: 0.6,
              child: Image(
                image: ThemeImage.image(
                  CombatDenSlots.streakIcon,
                  fallback: ApiImage.asset('streak_icon.png'),
                ),
                width: _kStreakIconWidth,
                height: _kStreakIconHeight,
                fit: BoxFit.contain,
              ),
            ),
            StaggeredReveal(
              delay: step,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingSmall,
                children: [
                  Text(
                    "You're checked in!",
                    textAlign: TextAlign.center,
                    style: DesignConstants.h1,
                  ),
                  Text(
                    className,
                    textAlign: TextAlign.center,
                    style: DesignConstants.p.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            StaggeredReveal(
              delay: step * 2,
              child: _StreakCountUp(
                streakWeeks: streakWeeks,
                delay: step * 2,
              ),
            ),
            StaggeredReveal(
              delay: step * 3,
              child: _PointsPill(pointsWorth: pointsWorth),
            ),
            StaggeredReveal(
              delay: step * 4,
              child: AppPrimaryButton(text: 'Done', onPressed: onDone),
            ),
          ],
        ),
      ),
    );
  }
}

/// The points earned, framed as a small primary-tinted token so it reads as a
/// reward rather than a caption.
class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.pointsWorth});

  final int pointsWorth;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.primaryCard,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCircle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingSmall,
        ),
        child: Text(
          '+$pointsWorth points',
          textAlign: TextAlign.center,
          style: DesignConstants.h2.copyWith(
            color: DesignConstants.primaryColor,
          ),
        ),
      ),
    );
  }
}

/// The streak number rolling up to [streakWeeks] with the "week streak" label
/// beneath — the streak celebration's count-up beat, standalone. [delay] holds
/// the roll until the block has revealed, so the number appears already moving.
class _StreakCountUp extends StatelessWidget {
  const _StreakCountUp({
    required this.streakWeeks,
    this.delay = Duration.zero,
  });

  final int streakWeeks;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CountUpText(
          target: streakWeeks,
          style: DesignConstants.big1_5,
          textAlign: TextAlign.center,
          delay: delay,
        ),
        Text(
          'week streak',
          textAlign: TextAlign.center,
          style: DesignConstants.big2,
        ),
      ],
    );
  }
}
