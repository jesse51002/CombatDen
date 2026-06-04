import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_member_info.dart';
import 'package:crm/features/member_details/data/models/paying_for_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/mark_paid_cash_dialog.dart';
import 'package:crm/features/member_details/presentation/dialogs/update_price_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/info_table.dart';

/// Status / type / billing cycle / cost / dates for the
/// current membership, with inline affordances:
/// - "Mark as paid with cash" when the membership is not
///   paid and not terminal.
/// - "Update price" when a covered person is billed at an
///   outdated price.
///
/// The covered subject for inline mutations is
/// [coveredMemberId] (the primary member's slot).
class MembershipDetailsTable extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final String coveredMemberId;

  const MembershipDetailsTable({
    super.key,
    required this.member,
    required this.membership,
    required this.coveredMemberId,
  });

  @override
  Widget build(BuildContext context) {
    final payers = membership.payingFor;
    final terminal = isTerminalStatus(membership.status);

    // Promote a whole-plan cancellation into the Status
    // cell when everyone on the plan is cancelling. Partial
    // cancellations stay inline in the paying-for list so
    // each person's timing is distinct.
    final allCancelling = !terminal &&
        payers.isNotEmpty &&
        payers.every(
          (p) =>
              membership.exitDateFor(p.memberId)?.kind ==
              MembershipExitKind.cancelling,
        );
    MembershipExitDate? latestCancel;
    if (allCancelling) {
      for (final p in payers) {
        final exit = membership.exitDateFor(p.memberId);
        if (exit == null) continue;
        if (latestCancel == null ||
            exit.date.isAfter(latestCancel.date)) {
          latestCancel = exit;
        }
      }
    }
    final singleExit = allCancelling ? latestCancel : null;

    final outdatedPayers = payers
        .where(
          (p) =>
              membership.isOnOutdatedPriceFor(p.memberId),
        )
        .toList();

    final planTypeLabel = membership.planType == null
        ? '—'
        : titleCase(membership.planType!);

    return InfoTable(
      rows: [
        (
          membershipLabel('Status:'),
          _StatusCell(
            member: member,
            membership: membership,
            coveredMemberId: coveredMemberId,
            singleExit: singleExit,
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
          _CostCell(
            membership: membership,
            outdatedPayers: outdatedPayers,
          ),
        ),
        (
          membershipLabel('Last paid:'),
          dateValue(membership.lastPaidDate),
        ),
        if (singleExit == null)
          (
            membershipLabel('Next due:'),
            dateValue(membership.nextDueDate),
          ),
        (
          membershipLabel('Start date:'),
          dateValue(membership.startDate),
        ),
        if (membership.status == MembershipStatus.frozen)
          (
            membershipLabel('Freeze start:'),
            dateValue(membership.freezeStartDate),
          ),
        if (membership.status == MembershipStatus.frozen)
          (
            membershipLabel('Freeze end:'),
            dateValue(membership.freezeEndDate),
          ),
      ],
    );
  }
}

class _StatusCell extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
  final String coveredMemberId;
  final MembershipExitDate? singleExit;

  const _StatusCell({
    required this.member,
    required this.membership,
    required this.coveredMemberId,
    required this.singleExit,
  });

  /// Whether to offer a "mark paid with cash" affordance —
  /// the membership is active/trial but not yet marked paid,
  /// and we can resolve the covered item.
  bool get _offerCash {
    if (isTerminalStatus(membership.status)) return false;
    if (member.isPaid) return false;
    return membership.itemIdFor(coveredMemberId) != null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        singleExit != null
            ? _ExitStatus(exit: singleExit!)
            : statusValue(membership.status),
        if (_offerCash)
          _InlineActionLink(
            text: 'Mark as paid with cash',
            onPressed: () => MarkPaidCashDialog.show(
              context: context,
              membership: membership,
              coveredMemberId: coveredMemberId,
              coveredMemberName: member.fullName,
            ),
          ),
      ],
    );
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

class _CostCell extends StatelessWidget {
  final MembershipInfo membership;
  final List<PayingForMember> outdatedPayers;

  const _CostCell({
    required this.membership,
    required this.outdatedPayers,
  });

  @override
  Widget build(BuildContext context) {
    final terminal = isTerminalStatus(membership.status);
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
                    'an old price.'
                : '${outdatedPayers.length} people are on '
                    'an old price.',
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.okYellow,
            ),
          ),
          ...outdatedPayers.map(
            (p) => _InlineActionLink(
              text: 'Update ${p.fullName}’s price',
              onPressed: () => UpdatePriceDialog.show(
                context: context,
                membership: membership,
                coveredMemberId: p.memberId,
                coveredMemberName: p.fullName,
              ),
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
