import 'package:crm/core/constants/design_constants.dart';
import 'package:flutter/material.dart';

import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/presentation/widgets/profile_header/linked_accounts_section.dart';
import 'package:crm/features/member_details/presentation/widgets/profile_header/profile_info_section.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Profile header with avatar, name, membership summary,
/// paid badge, action buttons, and linked accounts.
class ProfileHeaderSection extends StatelessWidget {
  final MemberDetailResponse member;
  final void Function(String crmUserId)?
      onLinkedAccountTap;

  const ProfileHeaderSection({
    super.key,
    required this.member,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      crossAxisAlignment: CrossAxisAlignment.center,
      padding: EdgeInsetsGeometry.all(DesignConstants.paddingBig),
      children: [
        ProfileInfoSection(member: member),
        if (member.linkedAccounts.isNotEmpty)
          LinkedAccountsSection(
            member: member,
            onLinkedAccountTap: onLinkedAccountTap,
          ),
      ],
    );
  }
}
