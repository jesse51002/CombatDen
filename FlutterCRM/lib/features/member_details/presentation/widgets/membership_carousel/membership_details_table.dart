import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
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
          membershipLabel('Type:'),
          Text(
            membership.planType != null
                ? membership.planType![0].toUpperCase() +
                    membership.planType!.substring(1)
                : '—',
            style: DesignConstants.h2.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        (
          membershipLabel(
            durationLabel(membership.planType),
          ),
          Text(
            formatDuration(
              membership.durationAmount,
              membership.durationUnit,
              membership.planType,
            ),
            style: DesignConstants.h2.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
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
        if (membership.endDate != null)
          (
            membershipLabel('End Date:'),
            dateValue(membership.endDate, dateFmt),
          ),
        if (membership.status == MembershipStatus.frozen)
          (
            membershipLabel('Freeze Start:'),
            dateValue(
              membership.freezeStartDate,
              dateFmt,
            ),
          ),
        if (membership.status == MembershipStatus.frozen)
          (
            membershipLabel('Freeze End:'),
            dateValue(
              membership.freezeEndDate,
              dateFmt,
            ),
          ),
      ],
    );
  }
}
