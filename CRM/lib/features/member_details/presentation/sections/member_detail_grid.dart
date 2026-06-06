import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/sections/member_waivers_section.dart';
import 'package:crm/features/member_details/presentation/sections/membership_carousel.dart';
import 'package:crm/features/member_details/presentation/sections/personal_info_section.dart';
import 'package:crm/features/member_details/presentation/sections/rank_section.dart';
import 'package:crm/features/member_details/presentation/sections/retention_section.dart';

/// Responsive body of the member detail screen.
///
/// Desktop (≥ [AppConstants.breakpointTablet]): a two-column grid —
/// personal info, rank, and retention stacked on the left, the membership
/// carousel on the right. The columns are stretched to equal height so
/// their bottoms align; the left column's retention card fills the slack.
/// Below the breakpoint everything stacks into a single column at natural
/// height.
class MemberDetailGrid extends StatelessWidget {
  final MemberDetailResponse member;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String> onLinkedAccountTap;

  const MemberDetailGrid({
    super.key,
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    required this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >=
            AppConstants.breakpointTablet;
        final left = _LeftColumn(member: member, expand: wide);
        final carousel = MembershipCarousel(
          member: member,
          currentIndex: currentIndex,
          onPageChanged: onPageChanged,
          onLinkedAccountTap: onLinkedAccountTap,
          payments: member.paymentHistory,
          expand: wide,
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [left, carousel],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: [
              Expanded(child: left),
              Expanded(child: carousel),
            ],
          ),
        );
      },
    );
  }
}

/// Left grid column: personal info, rank, and retention, stacked.
class _LeftColumn extends StatelessWidget {
  final MemberDetailResponse member;

  /// When true (wide grid), the retention card expands to fill the column
  /// so it bottom-aligns with the taller membership column. Must stay
  /// false in the stacked layout, where height is unbounded.
  final bool expand;

  const _LeftColumn({required this.member, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final retention = RetentionSection(
      retention: member.retention,
      rewards: member.recentlyRedeemedRewards,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        PersonalInfoSection(
          personalInfo: member.personalInfo,
        ),
        MemberWaiversSection(
          memberId: member.memberId,
          gymId: member.gymId,
        ),
        if (member.rank != null)
          RankSection(rank: member.rank!),
        if (expand) Expanded(child: retention) else retention,
      ],
    );
  }
}
