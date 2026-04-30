import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';

/// Avatar + full-name cell for the "Name" column.
class NameCell extends StatelessWidget {
  final Member member;
  const NameCell({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        ClipOval(
          child: Image.asset(
            member.avatarAsset,
            width: DesignConstants.tableRowHeight,
            height: DesignConstants.tableRowHeight,
            fit: BoxFit.cover,
          ),
        ),
        Expanded(
          child: Text(
            member.fullName,
            style: DesignConstants.h3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
