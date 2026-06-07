import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/info_table.dart';

/// Status / type / billing cycle / cost / usage / dates for
/// the **selected covered member** ([coveredMemberId]) on the
/// current membership. Everything reads atomically for that one
/// member: their status, their cost, their class usage. The
/// outdated-price prompt lives in its own card outside this
/// table; cash payment lives in the Invoices card.
class MembershipDetailsTable extends StatelessWidget {
  final MembershipInfo membership;
  final String coveredMemberId;

  const MembershipDetailsTable({
    super.key,
    required this.membership,
    required this.coveredMemberId,
  });

  MembershipStatus get _status =>
      membership.payingForMemberFor(coveredMemberId)?.status ??
      membership.status;

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final exit = membership.exitDateFor(coveredMemberId);
    final cancelling = exit != null &&
        exit.kind == MembershipExitKind.cancelling &&
        !isTerminalStatus(status);

    final usage =
        membership.payingForMemberFor(coveredMemberId);

    final planTypeLabel = membership.planType == null
        ? '—'
        : titleCase(membership.planType!);

    return InfoTable(
      rows: [
        (
          membershipLabel('Status:'),
          _StatusCell(
            status: status,
            exit: cancelling ? exit : null,
          ),
        ),
        (
          membershipLabel('Type:'),
          Text(
            planTypeLabel,
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
          costValue(
            membership.totalPriceFor(coveredMemberId),
          ),
        ),
        if (usage != null)
          (
            membershipLabel('Usage:'),
            Text(
              _usageText(usage),
              style: DesignConstants.h2.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        (
          membershipLabel('Last paid:'),
          dateValue(membership.lastPaidDate),
        ),
        if (!cancelling)
          (
            membershipLabel('Next due:'),
            dateValue(membership.nextDueDate),
          ),
        (
          membershipLabel('Start date:'),
          dateValue(membership.startDate),
        ),
        if (status == MembershipStatus.frozen)
          (
            membershipLabel('Freeze start:'),
            dateValue(membership.freezeStartDate),
          ),
        if (status == MembershipStatus.frozen)
          (
            membershipLabel('Freeze end:'),
            dateValue(membership.freezeEndDate),
          ),
      ],
    );
  }

  String _usageText(PayingForMember usage) {
    if (usage.classCount == null) {
      final cycle = membership.durationUnit.toLowerCase();
      return '${usage.classesUsed} classes this $cycle';
    }
    return '${usage.classesUsed}/'
        '${usage.classCount} classes';
  }
}

class _StatusCell extends StatelessWidget {
  final MembershipStatus status;
  final MembershipExitDate? exit;

  const _StatusCell({
    required this.status,
    required this.exit,
  });

  @override
  Widget build(BuildContext context) {
    return exit != null
        ? _ExitStatus(exit: exit!)
        : statusValue(status);
  }
}

class _ExitStatus extends StatelessWidget {
  final MembershipExitDate exit;

  const _ExitStatus({required this.exit});

  @override
  Widget build(BuildContext context) {
    final text =
        'Cancelling on ${formatShortDay(exit.date)}';
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
