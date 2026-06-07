import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/bloc/member_detail_bloc.dart';
import 'package:crm/features/member_details/bloc/member_detail_event.dart';
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

/// Applied discounts for the **selected covered member**
/// ([coveredMemberId]) only — every discount is a frozen,
/// item-scoped snapshot on that member's membership. Plus a
/// Manage Discounts entry point targeting that member's slot.
class DiscountsSection extends StatelessWidget {
  final MemberDetailResponse member;
  final MembershipInfo membership;
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
    final itemId = membership.itemIdFor(coveredMemberId);
    final discounts = membership.discounts
        .where((d) => itemId != null && d.itemId == itemId)
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
                AppDataTableColumn(label: '', minWidth: 44),
              ],
              rows: discounts
                  .map((d) => _row(context, d, itemId))
                  .toList(),
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
                      coveredMemberId: coveredMemberId,
                    )
                : null,
          ),
        ],
      ),
    );
  }

  AppDataTableRow _row(
    BuildContext context,
    DiscountInfo d,
    String? itemId,
  ) {
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
        _RemoveButton(
          itemId: itemId,
          memberId: coveredMemberId,
          appliedDiscountId: d.appliedDiscountId,
        ),
      ],
    );
  }
}

/// Removes a single applied-discount snapshot by its id —
/// the apply path deletes one row, never a replace-set.
class _RemoveButton extends StatelessWidget {
  final String? itemId;
  final String memberId;
  final String appliedDiscountId;

  const _RemoveButton({
    required this.itemId,
    required this.memberId,
    required this.appliedDiscountId,
  });

  @override
  Widget build(BuildContext context) {
    final id = itemId;
    return IconButton(
      tooltip: 'Remove discount',
      visualDensity: VisualDensity.compact,
      onPressed: id == null
          ? null
          : () => context.read<MemberDetailBloc>().add(
                ApplyDiscountsRequested(
                  itemId: id,
                  memberId: memberId,
                  removeAppliedIds: [appliedDiscountId],
                ),
              ),
      icon: Icon(
        Symbols.close_sharp,
        size: DesignConstants.iconSizeSmall,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.badRed,
      ),
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
