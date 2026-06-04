import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/sections/discounts_section.dart';
import 'package:crm/features/member_details/presentation/sections/membership_actions_row.dart';
import 'package:crm/features/member_details/presentation/sections/membership_details_table.dart';
import 'package:crm/features/member_details/presentation/sections/paying_for_section.dart';
import 'package:crm/features/member_details/presentation/sections/payment_history_section.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Paged membership card — one membership at a time with
/// prev/next navigation. Each page shows the plan header,
/// details table, the covered-people list, discounts,
/// payment history, and the account actions row.
class MembershipCarousel extends StatelessWidget {
  final MemberDetailResponse member;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String>? onLinkedAccountTap;
  final List<PaymentRecord> payments;

  const MembershipCarousel({
    super.key,
    required this.member,
    required this.currentIndex,
    required this.onPageChanged,
    this.onLinkedAccountTap,
    this.payments = const [],
  });

  List<MembershipInfo> get _memberships =>
      member.memberships;

  /// The covered subject for inline per-membership
  /// mutations: the primary member when they hold a slot on
  /// this membership, else the first covered person present.
  String _coveredSubject(MembershipInfo membership) {
    if (membership.itemIdFor(member.memberId) != null) {
      return member.memberId;
    }
    if (membership.members.isNotEmpty) {
      return membership.members.keys.first;
    }
    return member.memberId;
  }

  @override
  Widget build(BuildContext context) {
    if (_memberships.isEmpty) {
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

    final index =
        currentIndex.clamp(0, _memberships.length - 1);
    final membership = _memberships[index];
    final hasMultiple = _memberships.length > 1;
    final coveredId = _coveredSubject(membership);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingBig,
        children: [
          _CarouselHeader(
            membership: membership,
            currentIndex: index,
            total: _memberships.length,
            hasMultiple: hasMultiple,
            onPrevious: index > 0
                ? () => onPageChanged(index - 1)
                : null,
            onNext: index < _memberships.length - 1
                ? () => onPageChanged(index + 1)
                : null,
          ),
          MembershipDetailsTable(
            member: member,
            membership: membership,
            coveredMemberId: coveredId,
          ),
          if (membership.payingFor.isNotEmpty)
            PayingForSection(
              membership: membership,
              onLinkedAccountTap: onLinkedAccountTap,
            ),
          DiscountsSection(
            member: member,
            membership: membership,
            coveredMemberId: coveredId,
          ),
          PaymentHistorySection(payments: payments),
          MembershipActionsRow(
            member: member,
            currentMembership: membership,
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
