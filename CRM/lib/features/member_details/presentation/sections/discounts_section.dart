import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_dialog.dart';
import 'package:crm/features/member_details/presentation/widgets/member_detail_format.dart';
import 'package:crm/features/member_details/presentation/widgets/membership_display_helpers.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/invoice_breakdown/invoice_chip.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Active discounts applied to the current membership, plus
/// a Manage Discounts entry point. Edits target the primary
/// member's slot ([coveredMemberId]).
class DiscountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;

  /// The covered person whose discount set is managed —
  /// the primary member when present on the plan.
  final String coveredMemberId;

  const DiscountsSection({
    super.key,
    required this.member,
    required this.membership,
    required this.coveredMemberId,
  });

  bool get _canManage =>
      !isTerminalStatus(membership.status) &&
      membership.itemIdFor(coveredMemberId) != null;

  @override
  Widget build(BuildContext context) {
    final discounts = membership.discounts;
    return SubtitleSection(
      title: 'Discounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (discounts.isEmpty)
            _Empty()
          else
            AppDataTable(
              shrinkWrap: true,
              stickyHeader: false,
              columns: const [
                AppDataTableColumn(
                  label: 'Name',
                  fill: true,
                ),
                AppDataTableColumn(
                  label: 'Ends',
                  minWidth: 110,
                ),
                AppDataTableColumn(
                  label: 'Discount',
                  minWidth: 96,
                ),
              ],
              rows: discounts
                  .map((d) => _row(d))
                  .toList(),
            ),
          AppOutlineButton(
            fullWidth: true,
            text: 'Manage discounts',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: _canManage
                ? () => ManageDiscountsDialog.show(
                      context: context,
                      gymId: member.gymId,
                      membership: membership,
                      coveredMemberId: coveredMemberId,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  AppDataTableRow _row(DiscountInfo discount) {
    return AppDataTableRow(
      cells: [
        Text(
          discount.discountName,
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          formatDay(discount.endDate),
          style: DesignConstants.h3,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: InvoiceChip(
            label: discount.discountLabel,
            tone: InvoiceChipTone.good,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        DesignConstants.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(
          DesignConstants.radiusSmall,
        ),
      ),
      child: Center(
        child: Text(
          'No discounts',
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
