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

/// Applied discounts on this membership, grouped UNDER each
/// covered person's membership line so it is exact what is
/// discounted and what is not — every discount is a frozen,
/// item-scoped snapshot. Plus a Manage Discounts entry point
/// targeting the primary member's slot ([coveredMemberId]).
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

  /// Display name for a covered member id — resolved from
  /// the queried member, the paying-for roster, then linked
  /// accounts. Falls back to a generic label.
  String _nameFor(String memberId) {
    if (memberId == member.memberId) return member.fullName;
    for (final p in membership.payingFor) {
      if (p.memberId == memberId) return p.fullName;
    }
    for (final a in member.linkedAccounts) {
      if (a.memberId == memberId) return a.fullName;
    }
    return 'Member';
  }

  /// Covered member ids in a stable order: the managed
  /// member first, then any others on the plan group.
  List<String> get _coveredOrder {
    final ids = membership.members.keys.toList();
    ids.sort((a, b) {
      if (a == coveredMemberId) return -1;
      if (b == coveredMemberId) return 1;
      return 0;
    });
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final showPerson = membership.members.length > 1;
    return SubtitleSection(
      title: 'Discounts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingMedium,
        children: [
          if (membership.discounts.isEmpty)
            const _Empty()
          else
            for (final coveredId in _coveredOrder)
              _MemberDiscountGroup(
                memberName: _nameFor(coveredId),
                showName: showPerson,
                memberId: coveredId,
                itemId: membership.itemIdFor(coveredId),
                discounts: membership.discounts
                    .where(
                      (d) =>
                          membership.itemIdFor(coveredId) !=
                              null &&
                          d.itemId ==
                              membership.itemIdFor(coveredId),
                    )
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
}

/// One covered person's applied discounts under their
/// membership line. Hidden entirely when they have none, so
/// the section reads exactly what is and isn't discounted.
class _MemberDiscountGroup extends StatelessWidget {
  final String memberName;
  final bool showName;
  final String memberId;
  final String? itemId;
  final List<DiscountInfo> discounts;

  const _MemberDiscountGroup({
    required this.memberName,
    required this.showName,
    required this.memberId,
    required this.itemId,
    required this.discounts,
  });

  @override
  Widget build(BuildContext context) {
    if (discounts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (showName)
          Text(
            memberName,
            style: DesignConstants.h3.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
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
              .map((d) => _row(context, d))
              .toList(),
        ),
      ],
    );
  }

  AppDataTableRow _row(BuildContext context, DiscountInfo d) {
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
          memberId: memberId,
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
