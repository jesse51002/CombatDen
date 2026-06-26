import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/info_table.dart';

/// Status / type / billing cycle / cost / usage / dates for the
/// viewed member's current membership. Everything reads flat off
/// the one membership row: its status, its cost, its class usage.
/// When the member is in an authorization relationship, [payerName]
/// is set and a "Paid by" row (a small avatar + the payer's name)
/// leads the table so it stands out; the outdated-price prompt
/// lives in its own card.
class MembershipDetailsTable extends StatelessWidget {
  final MembershipInfo membership;

  /// The payer's display name + photo, for the leading "Paid by"
  /// row. Null for a member with no authorization relationship
  /// (the row is omitted — they always pay their own way).
  final String? payerName;
  final String? payerPhotoUrl;

  /// How much of this membership's charge has been refunded (minor
  /// units). When > 0 a "Refunded" row shows right under Cost; null /
  /// 0 omits it. Resolved by [MembershipDetailsLoader] for one-time /
  /// trial memberships only (a recurring membership's refunds live in
  /// Payment History, so it is left null).
  final int? refundedAmount;

  const MembershipDetailsTable({
    super.key,
    required this.membership,
    this.payerName,
    this.payerPhotoUrl,
    this.refundedAmount,
  });

  @override
  Widget build(BuildContext context) {
    final status = membership.status;
    final exit = membership.exitDate;
    final cancelling = exit != null &&
        exit.kind == MembershipExitKind.cancelling &&
        !isTerminalStatus(status);

    final planTypeLabel = membership.planType == null
        ? '—'
        : titleCase(membership.planType!);

    return InfoTable(
      rows: [
        if (payerName != null)
          (
            membershipLabel('Paid by:'),
            _PaidByValue(
              name: payerName!,
              photoUrl: payerPhotoUrl,
            ),
          ),
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
            style: DesignConstants.h2Bold,
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
            style: DesignConstants.h2Bold,
          ),
        ),
        (
          membershipLabel('Cost:'),
          costBreakdownValue(
            membership.baseCost,
            membership.totalPrice,
          ),
        ),
        if (refundedAmount != null && refundedAmount! > 0)
          (
            membershipLabel('Refunded:'),
            refundedValue(refundedAmount!),
          ),
        (
          membershipLabel('Usage:'),
          Text(
            _usageText(),
            style: DesignConstants.h2Bold,
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

  String _usageText() {
    if (membership.classCount == null) {
      final cycle = membership.durationUnit.toLowerCase();
      return '${membership.classesUsed} classes this $cycle';
    }
    return '${membership.classesUsed}/'
        '${membership.classCount} classes';
  }
}

/// The "Paid by" value cell — a small payer avatar followed by
/// their name, matching the table's value text style.
class _PaidByValue extends StatelessWidget {
  final String name;
  final String? photoUrl;

  const _PaidByValue({required this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        CircleAvatar(
          radius: DesignConstants.iconSizeLarge / 2,
          backgroundColor: DesignConstants.backgroundColor,
          backgroundImage:
              photoUrl != null ? NetworkImage(photoUrl!) : null,
          child: photoUrl == null
              ? Text(
                  initial,
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                )
              : null,
        ),
        Flexible(
          child: Text(
            name,
            style: DesignConstants.h2Bold,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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
        ),
      ),
    );
  }
}
