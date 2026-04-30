import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/home/data/mock_member_stats.dart';
import 'package:app_management/features/home/presentation/widgets/total_members_card/_subgroup_legend_dot.dart';
import 'package:app_management/features/home/presentation/widgets/total_members_card/total_members_arc.dart';
import 'package:app_management/shared/widgets/section_card.dart';

/// Top hero card on the dashboard — large semicircular arc with the
/// total-members count and an active/inactive legend.
class TotalMembersCard extends StatelessWidget {
  final MemberStatsSummary stats;

  const TotalMembersCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingBig,
        children: [
          _ArcWithCount(stats: stats),
          _LegendRow(stats: stats),
        ],
      ),
    );
  }
}

class _ArcWithCount extends StatelessWidget {
  final MemberStatsSummary stats;
  const _ArcWithCount({required this.stats});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      height: 200,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: TotalMembersArc(
              active: stats.active,
              inactive: stats.inactive,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              bottom: DesignConstants.paddingSmall,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingLarge,
              children: [
                Text(
                  '${stats.total}',
                  style: DesignConstants.big2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DesignConstants.text,
                  ),
                ),
                Text(
                  'Total Members',
                  style: DesignConstants.h1Regular.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final MemberStatsSummary stats;
  const _LegendRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        SubgroupLegendDot(
          color: DesignConstants.primaryColor,
          label: 'Active: ${stats.active}',
        ),
        SubgroupLegendDot(
          color: DesignConstants.darkPrimary,
          label: 'Inactive: ${stats.inactive}',
        ),
      ],
    );
  }
}
