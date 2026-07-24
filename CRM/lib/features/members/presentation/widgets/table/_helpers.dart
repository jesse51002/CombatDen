import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Status color for the "Last Class" recency bucket.
///
/// Mirrors the Figma color tokens (good-green / ok-yellow /
/// bad-red) directly off [DesignConstants].
Color lastClassColor(int daysAgo) {
  if (daysAgo <= 7) return DesignConstants.goodGreen;
  if (daysAgo <= 14) return DesignConstants.okYellow;
  return DesignConstants.badRed;
}

/// Display label for the "Last Class" cell, e.g. "3 days ago".
String lastClassLabel(int daysAgo) {
  if (daysAgo == 1) return '1 day ago';
  return '$daysAgo days ago';
}

/// Display label for the Incomplete view's "Waiting" cell — how long an
/// unfinished signup has been sitting there. The backend already floors
/// the count at 0 in the gym's own timezone, so 0 means the person
/// started today.
String waitingLabel(int daysWaiting) {
  if (daysWaiting <= 0) return 'Today';
  if (daysWaiting == 1) return '1 day';
  return '$daysWaiting days';
}

/// Severity color for the "Waiting" cell.
///
/// Fresh reads NEUTRAL, not green: someone who abandoned the kiosk today
/// is the easiest to finish, but they still need finishing — a green
/// "healthy" cue would read as "nothing to do here". It turns amber after
/// a week and red after two, when the person has likely moved on. Same
/// 7/14-day thresholds as [lastClassColor], deliberately, so "stale"
/// means one thing across this table.
Color waitingColor(int daysWaiting) {
  if (daysWaiting <= 7) return DesignConstants.text;
  if (daysWaiting <= 14) return DesignConstants.okYellow;
  return DesignConstants.badRed;
}
