import 'package:mobile_app/core/design_constants.dart';

/// Approximate heights of the pieces above the date rail.
///
/// They feed the scroll-position maths that decides which date pill is
/// highlighted, so a few pixels of drift is free — measuring at runtime
/// would cost a layout pass per frame to buy nothing.
const double kHomeTopbarHeight = 268;
const double kHomeUpcomingCardHeight = 290;
const double kHomeScheduleTitleHeight = 20;
const double kHomeDateRowHeight = 50;

/// Everything above the date rail. The booked page adds the upcoming
/// card and the schedule title, plus the section gap before each.
double homeHeaderHeight({required bool booked}) {
  if (!booked) return kHomeTopbarHeight;
  return kHomeTopbarHeight +
      DesignConstants.spacingBig +
      kHomeUpcomingCardHeight +
      DesignConstants.spacingBig +
      kHomeScheduleTitleHeight;
}
