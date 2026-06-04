import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';

/// Title + summary subtitle for the Members screen.
///
/// Shows the count of active, trial, frozen, and overdue
/// members from [totalCounts].
class MembersListHeader extends StatelessWidget {
  final MembersListTotalCounts totalCounts;

  const MembersListHeader({
    super.key,
    required this.totalCounts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text('Members', style: DesignConstants.big2),
        Text(
          '${totalCounts.active} active'
          ', ${totalCounts.trial} trial'
          ', ${totalCounts.frozen} frozen'
          ', ${totalCounts.overdue} overdue',
          style: DesignConstants.h1Regular.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
