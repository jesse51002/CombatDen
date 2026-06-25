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

/// Applied discounts for the viewed member's current membership —
/// every discount is a frozen, item-scoped snapshot on that
/// membership. Adding and removing both happen in the Manage
/// Discounts dialog (this table is read-only).
class DiscountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;

  const DiscountsSection({
    super.key,
    required this.member,
    required this.membership,
  });

  bool get _canManage => !isTerminalStatus(membership.status);

  @override
  Widget build(BuildContext context) {
    final itemId = membership.itemId;
    final discounts = membership.discounts
        .where((d) => d.itemId == itemId)
        .toList();

    return SubtitleSection(
      title: 'Discounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (discounts.isEmpty)
            const _Empty()
          else
            AppDataTable(
              shrinkWrap: true,
              stickyHeader: false,
              columns: const [
                AppDataTableColumn(label: 'Name', fill: true),
                AppDataTableColumn(label: 'Ends', minWidth: 110),
                AppDataTableColumn(
                  label: 'Discount',
                  minWidth: 96,
                ),
              ],
              rows: discounts.map(_row).toList(),
            ),
          AppOutlineButton(
            fullWidth: true,
            text: 'Manage discounts',
            borderRadius: DesignConstants.radiusSmall,
            onPressed: _canManage
                ? () => ManageDiscountsDialog.show(
                      context: context,
                      member: member,
                      membership: membership,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  AppDataTableRow _row(DiscountInfo d) {
    return AppDataTableRow(
      cells: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(
              d.discountName,
              style: DesignConstants.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (d.isLinked)
              Text(
                'Linked',
                style: DesignConstants.pSmall.copyWith(
                  color: DesignConstants.text3rd,
                ),
              ),
          ],
        ),
        Text(
          formatDay(d.endDate),
          style: DesignConstants.h3,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: InvoiceChip(
            label: d.discountLabel,
            tone: d.isLinked
                ? InvoiceChipTone.brand
                : InvoiceChipTone.good,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

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
