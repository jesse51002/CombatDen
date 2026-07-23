import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_streak_week_strip.dart';
import 'package:crm/shared/widgets/measured_max_width.dart';

/// The glance's left half — a static replica of the member app's resting streak
/// state (mockup `.streak`): the big sapphire week numeral over "week streak",
/// a keep-it-alive note, and the Monday→Sunday week strip. Vertically centred
/// in its panel like the app's resting composition.
class KioskStreakPanel extends StatelessWidget {
  final int weeks;
  final List<bool> daysCompleted;

  const KioskStreakPanel({
    super.key,
    required this.weeks,
    required this.daysCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return KioskGlancePanel(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          _StreakStack(weeks: weeks),
          // MeasuredMaxWidth, not ConstrainedBox: the note wraps at this
          // measure, and the glance equalizes its two panels with an
          // IntrinsicHeight — a plain cap would report the note's height at
          // the full panel width (one line) and overflow once it really wraps.
          MeasuredMaxWidth(
            maxWidth: DesignConstants.kioskGlanceMeasure,
            child: Text(
              'Come back this week to keep it alive.',
              style: DesignConstants.kioskBody.copyWith(
                color: DesignConstants.text2nd,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          KioskStreakWeekStrip(daysCompleted: daysCompleted),
        ],
      ),
    );
  }
}

class _StreakStack extends StatelessWidget {
  final int weeks;

  const _StreakStack({required this.weeks});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          '$weeks',
          style: DesignConstants.kioskStreakNum.copyWith(
            color: DesignConstants.primaryColor,
          ),
        ),
        Text(
          'week streak',
          style: DesignConstants.kioskMetric.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
