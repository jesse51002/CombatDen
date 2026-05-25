import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/members/data/mock_loyalty.dart';
import 'package:app_management/features/members/data/mock_member_history.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/loyalty_tab/redemptions_section.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/back_link.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/profile_header/profile_header.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/rank_section/rank_section.dart';
import 'package:app_management/features/members/presentation/widgets/specific_member/retention_section/retention_section.dart';
import 'package:app_management/shared/widgets/hairline.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// The member profile: back link, profile header, Info and Rank grids, then a
/// single Reward Redemptions grid (pending + approved together), separated by
/// hairline rules. Sits on the page; no card chrome.
class MemberProfile extends StatelessWidget {
  final DemoMember member;
  final MemberDetailStats stats;

  const MemberProfile({
    super.key,
    required this.member,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        BackLink(onTap: () => _onBack(context)),
        ProfileHeader(member: member),
        const Hairline(),
        SubtitleSection(
          title: 'Info',
          child: RetentionSection(stats: stats),
        ),
        const Hairline(),
        SubtitleSection(
          title: 'Rank',
          child: RankSection(member: member, stats: stats),
        ),
        const Hairline(),
        const RedemptionsSection(
          redemptions: kMockMemberRedemptions,
          title: 'Reward Redemptions',
        ),
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
