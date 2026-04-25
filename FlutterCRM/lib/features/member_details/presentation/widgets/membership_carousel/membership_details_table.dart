import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/mark_paid_cash/mark_paid_cash_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/update_price/update_price_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/info_table.dart';

/// Table showing membership status, cost, and dates.
class MembershipDetailsTable extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;

  const MembershipDetailsTable({
    super.key,
    required this.member,
    required this.membership,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMMM d, yyyy');
    // Promote the cancellation into the Status cell when
    // *everyone* on the plan is cancelling — billing will
    // stop for the whole membership. Naturally-ending
    // memberships stay active until their end date, so they
    // don't override the status. Partial cancellations stay
    // inline in the paying-for list so each person's timing
    // is distinct.
    final payers = membership.payingFor;
    final alreadyTerminal =
        membership.status == MembershipStatus.cancelled ||
            membership.status == MembershipStatus.ended;
    final allCancelling = !alreadyTerminal &&
        payers.isNotEmpty &&
        payers.every(
          (p) =>
              membership.exitDateFor(p.crmUserId)?.kind ==
              MembershipExitKind.cancelling,
        );
    MembershipExitDate? latestCancel;
    if (allCancelling) {
      for (final p in payers) {
        final exit = membership.exitDateFor(p.crmUserId);
        if (exit == null) continue;
        if (latestCancel == null ||
            exit.date.isAfter(latestCancel.date)) {
          latestCancel = exit;
        }
      }
    }
    final singleExit = allCancelling ? latestCancel : null;

    final outdatedPayers = membership.payingFor
        .where(
          (p) =>
              membership.isOnOutdatedPriceFor(p.crmUserId),
        )
        .toList();

    return InfoTable(
      rows: [
        (
          membershipLabel('Status:'),
          _StatusCell(
            member: member,
            membership: membership,
            singleExit: singleExit,
          ),
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
          _CostCell(
            member: member,
            membership: membership,
            outdatedPayers: outdatedPayers,
          ),
        ),
        (
          membershipLabel('Last Paid:'),
          dateValue(membership.lastPaidDate, dateFmt),
        ),
        if (singleExit == null)
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

class _StatusCell extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final MembershipExitDate? singleExit;

  const _StatusCell({
    required this.member,
    required this.membership,
    required this.singleExit,
  });

  @override
  Widget build(BuildContext context) {
    final terminal =
        membership.status == MembershipStatus.cancelled ||
            membership.status == MembershipStatus.ended;
    final isOverdue =
        membership.status == MembershipStatus.overdue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        singleExit != null
            ? _exitStatusValue(singleExit!)
            : statusValue(membership.status),
        if (isOverdue && !terminal)
          _InlineActionLink(
            text: 'Mark as paid with cash',
            onPressed: () => MarkPaidCashDialog.show(
              context: context,
              crmUserId: member.crmUserId,
              membership: membership,
            ),
          ),
      ],
    );
  }

  Widget _exitStatusValue(MembershipExitDate exit) {
    final dateLabel = DateFormat(
      'M/d',
    ).format(exit.date.toLocal());
    final text = 'Cancelling on $dateLabel';
    return Semantics(
      label: 'Membership status: $text',
      child: Text(
        text,
        style: DesignConstants.h2.copyWith(
          color: DesignConstants.okYellow,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CostCell extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final List outdatedPayers;

  const _CostCell({
    required this.member,
    required this.membership,
    required this.outdatedPayers,
  });

  @override
  Widget build(BuildContext context) {
    final terminal =
        membership.status == MembershipStatus.cancelled ||
            membership.status == MembershipStatus.ended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        costValue(membership),
        if (outdatedPayers.isNotEmpty && !terminal) ...[
          Text(
            outdatedPayers.length == 1
                ? '${outdatedPayers.first.fullName} is on '
                    'an old price. Update their price?'
                : '${outdatedPayers.length} people are on '
                    'an old price. Update their price?',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.okYellow,
            ),
          ),
          _InlineActionLink(
            text: 'Update price',
            onPressed: () => UpdatePriceDialog.show(
              context: context,
              member: member,
              membership: membership,
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineActionLink extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const _InlineActionLink({
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingTiny,
        ),
        child: Text(
          text,
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.primaryColor,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: DesignConstants.primaryColor,
          ),
        ),
      ),
    );
  }
}
