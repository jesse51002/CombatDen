import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';

/// Display label for a [MemberRank].
String rankLabel(MemberRank rank) {
  switch (rank) {
    case MemberRank.silver:
      return 'Silver';
    case MemberRank.gold:
      return 'Gold';
    case MemberRank.bronze:
      return 'Bronze';
    case MemberRank.unknown:
      return '—';
  }
}

/// Belt asset path for a [MemberRank].
String rankAsset(MemberRank rank) {
  switch (rank) {
    case MemberRank.silver:
      return 'assets/images/rank_silver.png';
    case MemberRank.gold:
      return 'assets/images/rank_gold.png';
    case MemberRank.bronze:
      return 'assets/images/rank_bronze.png';
    case MemberRank.unknown:
      return 'assets/images/rank_bronze.png';
  }
}

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
