import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/membership_display_helpers.dart';
import 'package:crm/shared/widgets/info_table.dart';

/// Table showing membership status, cost, and dates.
class MembershipDetailsTable extends StatelessWidget {
  final MembershipInfo membership;

  const MembershipDetailsTable({
    super.key,
    required this.membership,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMMM d, yyyy');

    return InfoTable(
      rows: [
        (
          membershipLabel('Status:'),
          statusValue(membership.status),
        ),
        (
          membershipLabel('Cost:'),
          costValue(membership),
        ),
        (
          membershipLabel('Last Paid:'),
          dateValue(membership.lastPaidDate, dateFmt),
        ),
        (
          membershipLabel('Next Due:'),
          dateValue(membership.nextDueDate, dateFmt),
        ),
        (
          membershipLabel('Start Date:'),
          Text(
            dateFmt.format(
              membership.startDate.toLocal(),
            ),
            style: DesignConstants.h2.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
