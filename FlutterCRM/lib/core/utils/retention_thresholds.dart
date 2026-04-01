import 'dart:ui';

import 'package:crm/core/constants/design_constants.dart';

/// Utility for determining retention stat colors
/// based on configurable thresholds.
///
/// Used across any screen that displays retention data.
class RetentionThreshold {
  // Last class thresholds (days since last class)
  static const int _lastClassGreenMax = 7;
  static const int _lastClassYellowMax = 14;

  // Class streak thresholds (weeks)
  static const int _streakGreenMin = 4;
  static const int _streakYellowMin = 2;

  RetentionThreshold._();

  /// Returns a color for the "Last Class" stat based on
  /// how many days since the member's last class.
  static Color getLastClassColor(int daysSinceLastClass) {
    if (daysSinceLastClass <= _lastClassGreenMax) {
      return DesignConstants.goodGreen;
    }
    if (daysSinceLastClass <= _lastClassYellowMax) {
      return DesignConstants.okYellow;
    }
    return DesignConstants.badRed;
  }

  /// Returns a color for the "Class Streak" stat based
  /// on the number of consecutive weeks.
  static Color getStreakColor(int streakWeeks) {
    if (streakWeeks >= _streakGreenMin) {
      return DesignConstants.goodGreen;
    }
    if (streakWeeks >= _streakYellowMin) {
      return DesignConstants.okYellow;
    }
    return DesignConstants.badRed;
  }
}
