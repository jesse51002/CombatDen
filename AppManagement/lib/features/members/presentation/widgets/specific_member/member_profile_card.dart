import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/back_link.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/profile_header/profile_header.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/rank_section/rank_section.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/retention_section/retention_section.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/rewards_section/rewards_section.dart';

/// The member profile: back link, profile header, rank/retention grids,
/// and recently-redeemed-rewards list. Sits on the page; no card chrome.
class MemberProfileCard extends StatelessWidget {
  final DemoMember member;
  final MemberDetailStats stats;
  final List<RedeemedReward> rewards;

  const MemberProfileCard({
    super.key,
    required this.member,
    required this.stats,
    required this.rewards,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        BackLink(onTap: () => _onBack(context)),
        ProfileHeader(member: member),
        RankSection(member: member, stats: stats),
        RetentionSection(stats: stats),
        RewardsSection(rewards: rewards),
      ],
    );
  }

  void _onBack(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.members);
    }
  }
}
