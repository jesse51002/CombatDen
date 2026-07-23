import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
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
    return Center(
      child: Padding(
        padding: EdgeInsets.all(DesignConstants.paddingBig),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Image(
              image: ThemeImage.image(
                CombatDenSlots.streakIcon,
                fallback: ApiImage.asset('streak_icon.png'),
              ),
              width: _kStreakIconWidth,
              height: _kStreakIconHeight,
              fit: BoxFit.contain,
            ),
            Column(
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
                  style:
                      DesignConstants.p.copyWith(color: DesignConstants.text2nd),
                ),
              ],
            ),
            _StreakCountUp(streakWeeks: streakWeeks),
            Text(
              '+$pointsWorth points',
              textAlign: TextAlign.center,
              style: DesignConstants.pBig
                  .copyWith(color: DesignConstants.primaryColor),
            ),
            AppPrimaryButton(text: 'Done', onPressed: onDone),
          ],
        ),
      ),
    );
  }
}

/// The streak number rolling up to [streakWeeks] with the "week streak" label
/// beneath — the streak celebration's count-up beat, standalone.
class _StreakCountUp extends StatelessWidget {
  const _StreakCountUp({required this.streakWeeks});

  final int streakWeeks;

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
