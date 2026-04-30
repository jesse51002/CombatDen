import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';

/// "Name" column cell — circular avatar + member's full name.
class MemberNameCell extends StatelessWidget {
  final Member member;

  const MemberNameCell({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        ClipOval(
          child: Image.asset(
            member.avatarAsset,
            width: 30,
            height: 30,
            fit: BoxFit.cover,
          ),
        ),
        Expanded(
          child: Text(
            member.fullName,
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
