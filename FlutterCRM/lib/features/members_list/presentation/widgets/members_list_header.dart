import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';

/// Page header showing "Members" title and a subtitle
/// with total counts.
class MembersListHeader extends StatelessWidget {
  final MembersListTotalCounts? totalCounts;

  const MembersListHeader({
    super.key,
    this.totalCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members',
            style: DesignConstants.big2,
          ),
          const SizedBox(
            height: DesignConstants.spacingSmall,
          ),
          Text(
            _subtitle(),
            style: DesignConstants.h1.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      );
  }

  String _subtitle() {
    if (totalCounts == null) return '—';

    final parts = <String>[];
    parts.add(
      '${totalCounts!.active} active members',
    );
    parts.add(
      '${totalCounts!.trial} trial members',
    );
    parts.add(
      '${totalCounts!.frozen} frozen members',
    );
    parts.add(
      '${totalCounts!.overdue} overdue members',
    );
    return parts.join(', ');
  }
}
