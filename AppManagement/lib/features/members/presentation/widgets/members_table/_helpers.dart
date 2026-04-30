import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';

/// Display label for a [MemberRank] (capitalized — the real API will
/// hand us a lowercase string like `'silver'`, so the screen formats
/// it the way the API will eventually deliver it).
String rankLabel(MemberRank rank) {
  switch (rank) {
    case MemberRank.silver:
      return 'Silver';
    case MemberRank.gold:
      return 'Gold';
    case MemberRank.bronze:
      return 'Bronze';
    case MemberRank.unknown:
      return 'Unranked';
  }
}

/// Local asset path for a [MemberRank]'s belt icon.
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

/// Human-friendly recency label, e.g. `'3 days ago'`.
String recencyLabel(int daysAgo) {
  if (daysAgo <= 0) return 'Today';
  if (daysAgo == 1) return '1 day ago';
  return '$daysAgo days ago';
}

/// Color bucket for the "Last Class" column. Mirrors the Figma frame:
///   <= 7 days  → goodGreen
///   <= 14 days → okYellow
///   > 14 days  → badRed
Color recencyColor(int daysAgo) {
  if (daysAgo <= 7) return DesignConstants.goodGreen;
  if (daysAgo <= 14) return DesignConstants.okYellow;
  return DesignConstants.badRed;
}
