import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_members.dart';
import 'package:app_management/features/members/presentation/widgets/table/_helpers.dart';

/// "Rank" column cell — belt icon + rank label.
class MemberRankCell extends StatelessWidget {
  final MemberRank rank;

  const MemberRankCell({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Image.asset(
          rankAsset(rank),
          width: 30,
          height: 30,
          fit: BoxFit.contain,
        ),
        Expanded(
          child: Text(
            rankLabel(rank),
            style: DesignConstants.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
