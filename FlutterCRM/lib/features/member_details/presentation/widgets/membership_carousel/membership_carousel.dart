import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/payment_record.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/membership_actions_row.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/carousel_header.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/discounts_section.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/membership_details_table.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/paying_for_section.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_carousel/payment_history_section.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Paginated membership card showing one membership at a
/// time with left/right navigation arrows.
class MembershipCarousel extends StatelessWidget {
  final List<MembershipInfo> memberships;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final void Function(String crmUserId)?
      onLinkedAccountTap;
  final List<PaymentRecord> payments;

  const MembershipCarousel({
    super.key,
    required this.memberships,
    required this.currentIndex,
    required this.onPageChanged,
    this.onLinkedAccountTap,
    this.payments = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (memberships.isEmpty) {
      return SectionCard(
        title: 'Membership',
        children: [
          Text(
            'No memberships',
            style: DesignConstants.h2.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ],
      );
    }

    final membership = memberships[currentIndex];
    final hasMultiple = memberships.length > 1;

    return SectionCard(
      spacing: DesignConstants.spacingBig,
      children: [
        CarouselHeader(
          membership: membership,
          currentIndex: currentIndex,
          total: memberships.length,
          hasMultiple: hasMultiple,
          onPrevious: currentIndex > 0
              ? () => onPageChanged(currentIndex - 1)
              : null,
          onNext: currentIndex < memberships.length - 1
              ? () => onPageChanged(currentIndex + 1)
              : null,
        ),
        MembershipDetailsTable(
          membership: membership,
        ),
        if (membership.payingFor.isNotEmpty)
          PayingForSection(
            membership: membership,
            memberships: memberships,
            onLinkedAccountTap: onLinkedAccountTap,
          ),
        DiscountsSection(
          membership: membership,
        ),
        Expanded(
          child: PaymentHistorySection(
            payments: payments,
          ),
        ),
        MembershipActionsRow(
          memberships: memberships,
        ),
      ],
    );
  }
}
