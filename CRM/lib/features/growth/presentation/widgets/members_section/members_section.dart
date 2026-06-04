import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/mock_growth.dart';
import 'package:crm/features/growth/presentation/widgets/members_section/_date_range_pill.dart';
import 'package:crm/features/growth/presentation/widgets/members_section/_members_breakdown_table.dart';
import 'package:crm/features/growth/presentation/widgets/members_section/_members_trend_chart.dart';

/// Full-width "Members" section on Growth — title row with a date-range
/// pill, big "140 members" total, the trend chart, then the per-month
/// breakdown table. Sits on the page; no card chrome.
class MembersSection extends StatelessWidget {
  const MembersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        _Header(),
        Center(
          child: Text(
            '140 members',
            style: DesignConstants.big2Light,
          ),
        ),
        MembersTrendChart(),
        MembersBreakdownTable(rows: kMockMembersMonthRows),
      ],
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
