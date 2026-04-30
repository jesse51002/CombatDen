import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/members_table/_helpers.dart';

/// Belt icon + rank label for the "Rank" column.
class RankCell extends StatelessWidget {
  final MemberRank rank;
  const RankCell({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Image.asset(
          rankAsset(rank),
          width: DesignConstants.tableRowHeight,
          height: DesignConstants.tableRowHeight,
          fit: BoxFit.contain,
        ),
        Expanded(
          child: Text(
            rankLabel(rank),
            style: DesignConstants.h3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
