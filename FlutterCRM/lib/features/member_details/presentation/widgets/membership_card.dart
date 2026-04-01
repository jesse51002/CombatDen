import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/discount_card.dart';
import 'package:crm/features/member_details/presentation/widgets/linked_account_chip.dart';
import 'package:crm/shared/widgets/info_row.dart';
import 'package:crm/shared/widgets/outlined_action_button.dart';
import 'package:crm/shared/widgets/section_card.dart';

/// Card displaying membership details including status,
/// cost, dates, linked accounts, and discounts.
class MembershipCard extends StatelessWidget {
  final MembershipInfo membership;
  final void Function(String crmUserId)?
      onLinkedAccountTap;

  const MembershipCard({
    super.key,
    required this.membership,
    this.onLinkedAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMMM d, yyyy');

    return SectionCard(
      title: 'Membership',
      children: [
        InfoRow(label: 'Name', value: membership.planName),
        _StatusRow(status: membership.status),
        _CostRow(membership: membership),
        InfoRow(
          label: 'Last Paid',
          value: membership.lastPaidDate != null
              ? dateFmt.format(
                  membership.lastPaidDate!.toLocal(),
                )
              : null,
        ),
        InfoRow(
          label: 'Next Due',
          value: membership.nextDueDate != null
              ? dateFmt.format(
                  membership.nextDueDate!.toLocal(),
                )
              : null,
        ),
        InfoRow(
          label: 'Start Date',
          value: dateFmt.format(
            membership.startDate.toLocal(),
          ),
        ),
        // Linked Accounts
        if (membership.linkedAccounts.isNotEmpty) ...[
          const SizedBox(
            height:
                DesignConstants.spacingLarge,
          ),
          Text(
            'Linked Accounts',
            style: DesignConstants.h3,
          ),
          const SizedBox(
            height:
                DesignConstants.spacingSmall,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(
              DesignConstants.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.cardBackground,
              borderRadius: BorderRadius.circular(
                DesignConstants.radiusSmall,
              ),
            ),
            child: Wrap(
              spacing: DesignConstants.spacingMedium
                  ,
              runSpacing: DesignConstants.spacingSmall
                  ,
              children: membership.linkedAccounts
                  .map(
                    (a) => LinkedAccountChip(
                      account: a,
                      onTap: onLinkedAccountTap != null
                          ? () => onLinkedAccountTap!(
                                a.crmUserId,
                              )
                          : null,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(
            height:
                DesignConstants.spacingSmall,
          ),
          OutlinedActionButton(
            label: 'Manage Linked accounts',
            onPressed: () {
              // TODO: Navigate to linked accounts management
            },
          ),
        ],
        // Discounts
        if (membership.discounts.isNotEmpty) ...[
          const SizedBox(
            height:
                DesignConstants.spacingLarge,
          ),
          Text('Discounts', style: DesignConstants.h3),
          const SizedBox(
            height:
                DesignConstants.spacingSmall,
          ),
          ...membership.discounts.map(
            (d) => Padding(
              padding: const EdgeInsets.only(
                bottom:
                    DesignConstants.spacingSmall,
              ),
              child: DiscountCard(discount: d),
            ),
          ),
          OutlinedActionButton(
            label: 'Manage Discounts',
            onPressed: () {
              // TODO: Navigate to discounts management
            },
          ),
        ],
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String status;

  const _StatusRow({required this.status});

  Color get _statusColor {
    switch (status.toLowerCase()) {
      case 'active':
        return DesignConstants.goodGreen;
      case 'frozen':
        return DesignConstants.okYellow;
      case 'cancelled':
      case 'inactive':
        return DesignConstants.badRed;
      default:
        return DesignConstants.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: DesignConstants.spacingSmall,
      ),
      child: Row(
        children: [
          Text(
            'Status: ',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          Semantics(
            label: 'Membership status: $status',
            child: Text(
              status,
              style: DesignConstants.p.copyWith(
                color: _statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  final MembershipInfo membership;

  const _CostRow({required this.membership});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: DesignConstants.spacingSmall,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost: ',
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${membership.costFormula} = ',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                  TextSpan(
                    text:
                        '\$${membership.totalCost.toStringAsFixed(0)}',
                    style: DesignConstants.h3.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
