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
