import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_glance_panel.dart';
import 'package:crm/features/kiosk/presentation/widgets/kiosk_streak_week_strip.dart';
import 'package:crm/shared/widgets/animation/count_up_text.dart';
import 'package:crm/shared/widgets/measured_max_width.dart';

/// The glance's left half — a replica of the member app's resting streak
/// state: the big sapphire week numeral over "week streak", a keep-it-alive
/// note, and the Monday→Sunday week strip.
///
/// The numeral ROLLS UP to [weeks] on the member app's own odometer
/// ([CountUpText], at the app's celebration length) rather than a curve
/// invented here, so the kiosk celebrates in the same language. It starts on
/// the beat the panel fades in on, so the number is already moving as the
/// panel lands. Reduced motion gets the final number immediately.
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
          // MeasuredMaxWidth, not ConstrainedBox: the glance's IntrinsicHeight
          // would measure this note as one line and overflow once it wraps.
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
    final numeral = DesignConstants.kioskStreakNum.copyWith(
      color: DesignConstants.primaryColor,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingTiny,
      children: [
        if (MediaQuery.disableAnimationsOf(context))
          Text('$weeks', style: numeral)
        else
          CountUpText(
            target: weeks,
            style: numeral,
            duration: KioskRevealTimings.countUp,
            delay: KioskRevealTimings.panels,
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
