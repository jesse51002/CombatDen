import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Hardcoded, demo-only data for the Growth (analytics) screen.
///
/// Field names mirror what the real API will eventually return so the
/// repository swap is mechanical. Models are plain Dart classes; no
/// `fromJson` yet.

class GrowthRevenue {
  final int totalMembers;
  final int activeMembers;
  final int inactiveMembers;
  const GrowthRevenue({
    required this.totalMembers,
    required this.activeMembers,
    required this.inactiveMembers,
  });
}

class GrowthKpi {
  final String label;
  final IconData icon;
  final String value;
  final String deltaLabel;
  final String comparisonLabel;
  const GrowthKpi({
    required this.label,
    required this.icon,
    required this.value,
    required this.deltaLabel,
    required this.comparisonLabel,
  });
}

class MembersTrendPoint {
  final String monthLabel;
  final int total;
  const MembersTrendPoint({
    required this.monthLabel,
    required this.total,
  });
}

class MembersMonthRow {
  final String month;
  final int gain;
  final int churn;
  final int retain;
  final int total;
  const MembersMonthRow({
    required this.month,
    required this.gain,
    required this.churn,
    required this.retain,
    required this.total,
  });
}

class DonutStatRow {
  final String month;
  /// Pre-formatted right-side value, e.g. "9% (11 members)".
  final String value;
  const DonutStatRow({required this.month, required this.value});
}

class DonutChartData {
  /// 0.0..1.0 — the % shown in the ring and as the headline.
  final double progress;
  /// Headline to render in the donut center, e.g. "9%" or "64%".
  final String headline;
  /// Sub-label under the headline.
  final String subLabel;
  /// Color of the progress arc.
  final Color color;
  const DonutChartData({
    required this.progress,
    required this.headline,
    required this.subLabel,
    required this.color,
  });
}

const GrowthRevenue kMockGrowthRevenue = GrowthRevenue(
  totalMembers: 154,
  activeMembers: 123,
  inactiveMembers: 31,
);

// Order matches Figma: Total / Trial / New / Lost.
final List<GrowthKpi> kMockGrowthKpis = [
  GrowthKpi(
    label: 'Total Members',
    icon: Icons.group, // replaced with Symbols at use site
    value: '140',
    deltaLabel: '+11%',
    comparisonLabel: 'vs 124 last month',
  ),
  GrowthKpi(
    label: 'Trial Members',
    icon: Icons.card_giftcard,
    value: '24',
    deltaLabel: '+20%',
    comparisonLabel: 'vs 5 last month',
  ),
  GrowthKpi(
    label: 'New Members',
    icon: Icons.trending_up,
    value: '15',
    deltaLabel: '+300%',
    comparisonLabel: 'vs 5 last month',
  ),
  GrowthKpi(
    label: 'Lost Members',
    icon: Icons.trending_down,
    value: '11',
    deltaLabel: '-20%',
    comparisonLabel: 'vs 15 last month',
  ),
];

const List<String> kMockMembersTrendXLabels = [
  'Feb\n2025',
  'Apr\n2025',
  'Jun\n2025',
  'Aug\n2025',
  'Oct\n2025',
  'Dec\n2025',
  'Feb\n2026',
];

const List<int> kMockMembersTrendYTicks = [140, 70, 0];

const List<MembersMonthRow> kMockMembersMonthRows = [
  MembersMonthRow(
    month: 'February 2026',
    gain: 15,
    churn: 11,
    retain: 125,
    total: 140,
  ),
  MembersMonthRow(
    month: 'January 2025',
    gain: 5,
    churn: 6,
    retain: 110,
    total: 126,
  ),
  MembersMonthRow(
    month: 'December 2025',
    gain: 10,
    churn: 20,
    retain: 96,
    total: 113,
  ),
  MembersMonthRow(
    month: 'November 2025',
    gain: 8,
    churn: 4,
    retain: 120,
    total: 123,
  ),
  MembersMonthRow(
    month: 'October 2025',
    gain: 14,
    churn: 8,
    retain: 105,
    total: 112,
  ),
];

// ---- Monthly Churn donut card ----
final DonutChartData kMockChurnLast30 = DonutChartData(
  progress: 0.09,
  headline: '9%',
  subLabel: 'In Last 30 days',
  color: DesignConstants.primaryColor,
);

final DonutChartData kMockChurnGymAverage = DonutChartData(
  progress: 0.12,
  headline: '12%',
  subLabel: 'Gym Average',
  color: DesignConstants.primaryColor,
);

const List<DonutStatRow> kMockChurnRows = [
  DonutStatRow(month: 'February 2026', value: '9% (11 members)'),
  DonutStatRow(month: 'January 2025', value: '5% (6 members)'),
  DonutStatRow(month: 'December 2025', value: '14% (20 members)'),
  DonutStatRow(month: 'November 2025', value: '6% (4 members)'),
];

// ---- Trial Conversion donut card ----
final DonutChartData kMockConversionLast30 = DonutChartData(
  progress: 0.64,
  headline: '64%',
  subLabel: 'In Last 30 days',
  color: DesignConstants.primaryColor,
);

final DonutChartData kMockConversionGymAverage = DonutChartData(
  progress: 0.52,
  headline: '52%',
  subLabel: 'Gym Average',
  color: DesignConstants.primaryColor,
);

const List<DonutStatRow> kMockConversionRows = [
  DonutStatRow(month: 'February 2026', value: '64% (16 members)'),
  DonutStatRow(month: 'January 2025', value: '52% (9 members)'),
  DonutStatRow(month: 'December 2025', value: '42% (10 members)'),
  DonutStatRow(month: 'November 2025', value: '65% (17 members)'),
];
