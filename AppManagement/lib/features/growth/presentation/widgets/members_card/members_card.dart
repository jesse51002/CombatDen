import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/features/growth/presentation/widgets/members_card/_date_range_pill.dart';
import 'package:app_management/features/growth/presentation/widgets/members_card/_members_breakdown_table.dart';
import 'package:app_management/features/growth/presentation/widgets/members_card/_members_trend_chart.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// Wide "Members" card spanning the full width of Growth — title row
/// with a date-range pill, big "140 members" total, the trend chart,
/// then the per-month breakdown table.
class MembersCard extends StatelessWidget {
  const MembersCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingBig,
        children: [
          _Header(),
          Center(
            child: Text(
              '140 members',
              style: DesignConstants.big2.copyWith(
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          MembersTrendChart(),
          MembersBreakdownTable(rows: kMockMembersMonthRows),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Members',
            style: DesignConstants.h1,
          ),
        ),
        DateRangePill(
          rangeLabel: 'Feb 2025 - Now',
          granularityLabel: 'Year',
          onRangeTap: () =>
              debugPrint('[Growth] tap date range Feb 2025 - Now'),
          onGranularityTap: () =>
              debugPrint('[Growth] tap granularity Year'),
        ),
      ],
    );
  }
}
