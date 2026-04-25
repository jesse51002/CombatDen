import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/presentation/widgets/dialogs/manage_discounts/manage_discounts_dialog.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/shared/widgets/app_data_table.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// Section listing active discounts on a membership.
class DiscountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;

  const DiscountsSection({
    super.key,
    required this.member,
    required this.membership,
  });

  bool get _isTerminal =>
      membership.status == MembershipStatus.cancelled ||
      membership.status == MembershipStatus.ended;

  double get _tableHeight {
    if (membership.discounts.isEmpty) return 100;
    const headerHeight =
        DesignConstants.tableRowHeight;
    const gap = DesignConstants.spacingMedium;
    final rowsHeight = membership.discounts.length *
        DesignConstants.tableRowHeight;
    final separatorsHeight =
        (membership.discounts.length - 1) *
            (DesignConstants.spacingLarge * 2 + 2);
    return headerHeight + gap + rowsHeight + separatorsHeight;
  }

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Discounts',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.paddingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        child: Column(
          spacing: DesignConstants.spacingSmall,
          children: [
            SizedBox(
              height: _tableHeight,
              child: membership.discounts.isEmpty
                  ? Center(
                      child: Text(
                        'No discounts',
                        style:
                            DesignConstants.h2.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                      ),
                    )
                  : AppDataTable(
                      stickyHeader: false,
                      columns: const [
                        AppDataTableColumn(
                          label: 'Name',
                          fill: true,
                        ),
                        AppDataTableColumn(
                          label: 'Ends',
                          minWidth: 100,
                        ),
                        AppDataTableColumn(
                          label: 'Discount',
                          minWidth: 80,
                        ),
                      ],
                      rows: membership.discounts
                          .map((d) => _buildRow(d))
                          .toList(),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal:
                    DesignConstants.paddingSmall,
              ),
              child: AppOutlineButton(
                fullWidth: true,
                text: 'Manage Discounts',
                onPressed: _isTerminal
                    ? null
                    : () => ManageDiscountsDialog.show(
                          context: context,
                          crmUserId: member.crmUserId,
                          gymId: member.gymId,
                          membership: membership,
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppDataTableRow _buildRow(DiscountInfo discount) {
    final dateFmt = DateFormat('M/dd/yyyy');

    return AppDataTableRow(
      cells: [
        Text(
          discount.discountName,
          style: DesignConstants.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          discount.endDate != null
              ? dateFmt.format(
                  discount.endDate!.toLocal(),
                )
              : '—',
          style: DesignConstants.h3,
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.spacingSmall,
            vertical: DesignConstants.spacingTiny,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: DesignConstants.goodGreen,
            ),
            borderRadius: BorderRadius.circular(
              DesignConstants.radiusBig,
            ),
          ),
          child: Text(
            discount.discountLabel,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.goodGreen,
            ),
          ),
        ),
      ],
    );
  }
}
