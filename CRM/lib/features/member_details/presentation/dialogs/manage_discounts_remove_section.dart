import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_info.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_message.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// The **Remove** screen of the manage-discounts dialog: the
/// discount snapshots already applied to this member's line,
/// selectable for removal. Mirrors the per-row red × on the
/// section table — selecting here marks the snapshot for the
/// dialog's combined apply/remove commit.
class ManageDiscountsRemoveSection extends StatelessWidget {
  final List<DiscountInfo> applied;
  final Set<String> selectedToRemove;
  final ValueChanged<String> onToggle;

  const ManageDiscountsRemoveSection({
    super.key,
    required this.applied,
    required this.selectedToRemove,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (applied.isEmpty) {
      return const ManageDiscountsMessage(
        text: 'No discounts to remove.',
        icon: Symbols.info_sharp,
      );
    }
    final options = applied
        .map(
          (d) => DiscountOption(
            id: d.appliedDiscountId,
            name: d.discountName,
            valueLabel: d.discountLabel,
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Remove a discount',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        DiscountGrid(
          discounts: options,
          selectedIds: selectedToRemove,
          onToggle: (d) => onToggle(d.id),
        ),
      ],
    );
  }
}
