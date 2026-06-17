import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/sections/discounts_section.dart';
import 'package:crm/features/member_details/presentation/sections/membership_actions_row.dart';
import 'package:crm/features/member_details/presentation/sections/membership_details_table.dart';
import 'package:crm/features/member_details/presentation/sections/outdated_price_card.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/features/tasks/bloc/tasks_bloc.dart';
import 'package:crm/features/tasks/bloc/tasks_state.dart';
import 'package:crm/features/tasks/presentation/widgets/in_task_badge.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Paged membership card — one of the **viewed member's own**
/// memberships at a time with prev/next navigation. Each page
/// shows that membership's plan header, a "Paid by" banner (for
/// a member in a linked relationship), the details table, the
/// outdated-price prompt, discounts, and the account actions
/// row. A linked family member's memberships live on their own
/// page — reach them from the linked-accounts block.
class MembershipCarousel extends StatelessWidget {
  final MemberDetailResponse member;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const MembershipCarousel({
    super.key,
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
  });

  List<MembershipInfo> get _memberships => member.memberships;

  /// The payer of this membership — the viewed member (named,
  /// never "Self") or a linked account — with their photo, or
  /// null when no payer is resolvable.
  ({String name, String? photoUrl})? _payer(
    MembershipInfo membership,
  ) {
    final payerId = membership.paidByFor(member.memberId);
    if (payerId == null) return null;
    if (payerId == member.memberId) {
      return (name: member.fullName, photoUrl: member.photoUrl);
    }
    for (final account in member.linkedAccounts) {
      if (account.memberId == payerId) {
        return (name: account.fullName, photoUrl: account.photoUrl);
      }
    }
    return (name: 'Linked account', photoUrl: null);
  }

  @override
  Widget build(BuildContext context) {
    if (_memberships.isEmpty) {
      return _EmptyMembershipCard();
    }

    final index =
        currentIndex.clamp(0, _memberships.length - 1);
    final membership = _memberships[index];
    final hasMultiple = _memberships.length > 1;
    final coveredId = member.memberId;

    final status =
        membership.payingForMemberFor(coveredId)?.status ??
            membership.status;

    // Whether this membership's row is currently in an upgrade task.
    final itemId = membership.itemIdFor(coveredId);
    final tasksState = context.watch<TasksBloc>().state;
    final inTaskIds = switch (tasksState) {
      TasksLoaded(:final inTaskItemIds) => inTaskItemIds,
      TaskPolling(:final inTaskItemIds) => inTaskItemIds,
      TaskPollingDone(:final inTaskItemIds) => inTaskItemIds,
      _ => const <String>{},
    };
    final isInTask = itemId != null && inTaskIds.contains(itemId);

    final showOutdated = !isInTask &&
        !isTerminalStatus(status) &&
        membership.isOnOutdatedPriceFor(coveredId) &&
        membership.currentActivePrice != null;

    // The "Paid by" line shows for any member in a linked
    // relationship (parent or child); an unlinked solo member
    // always pays their own way, so it is omitted.
    final payer =
        member.linkedAccounts.isNotEmpty ? _payer(membership) : null;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        _CarouselHeader(
          membership: membership,
          currentIndex: index,
          total: _memberships.length,
          hasMultiple: hasMultiple,
          onPrevious:
              index > 0 ? () => onPageChanged(index - 1) : null,
          onNext: index < _memberships.length - 1
              ? () => onPageChanged(index + 1)
              : null,
        ),
        MembershipDetailsTable(
          membership: membership,
          coveredMemberId: coveredId,
          // A "Paid by" row leads the table for a linked member;
          // null for a solo (they always pay their own way).
          payerName: payer?.name,
          payerPhotoUrl: payer?.photoUrl,
        ),
        if (isInTask) const InTaskBadge(),
        if (showOutdated)
          OutdatedPriceCard(
            membership: membership,
            coveredMemberId: coveredId,
            coveredMemberName: member.fullName,
          ),
        DiscountsSection(
          member: member,
          membership: membership,
          coveredMemberId: coveredId,
        ),
      ],
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: DesignConstants.spacingBig,
        children: [
          // In the wide grid this card is the right column's filler:
          // BalancedColumns lays it at its natural size first (so the
          // content always fits), then may re-lay it TIGHT and taller —
          // the slack lands between the details and the bottom-pinned
          // actions row (`spacing` stays the minimum gap; under the
          // stacked layout's unbounded height spaceBetween is a no-op).
          // NEVER make this card scroll.
          details,
          MembershipActionsRow(
            member: member,
            currentMembership: membership,
            isInTask: isInTask,
          ),
        ],
      ),
    );
  }
}

class _EmptyMembershipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('Membership', style: DesignConstants.h2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              DesignConstants.paddingBig,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.backgroundColor,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
            child: Center(
              child: Text(
                'No memberships',
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselHeader extends StatelessWidget {
  final MembershipInfo membership;
  final int currentIndex;
  final int total;
  final bool hasMultiple;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _CarouselHeader({
    required this.membership,
    required this.currentIndex,
    required this.total,
    required this.hasMultiple,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasMultiple)
          Semantics(
            label: 'Previous membership',
            child: IconButton(
              onPressed: onPrevious,
              tooltip: 'Previous membership',
              icon: Icon(
                Symbols.chevron_left_sharp,
                color: onPrevious != null
                    ? DesignConstants.text
                    : DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              Text(
                membership.displayName,
                style: DesignConstants.h1,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasMultiple)
                Semantics(
                  label:
                      'Membership ${currentIndex + 1} of '
                      '$total',
                  child: Text(
                    '${currentIndex + 1} / $total '
                    'memberships',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasMultiple)
          Semantics(
            label: 'Next membership',
            child: IconButton(
              onPressed: onNext,
              tooltip: 'Next membership',
              icon: Icon(
                Symbols.chevron_right_sharp,
                color: onNext != null
                    ? DesignConstants.text
                    : DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
      ],
    );
  }
}
