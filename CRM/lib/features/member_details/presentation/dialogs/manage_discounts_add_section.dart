import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/member_details/presentation/dialogs/manage_discounts_message.dart';
import 'package:crm/features/member_details/presentation/widgets/discount_lifetime_label.dart';
import 'package:crm/shared/widgets/discount_grid.dart';

/// The **Add** screen of the manage-discounts dialog: the
/// gym's not-yet-applied presets to add (already-applied
/// presets are filtered out upstream), or the load-failed /
/// nothing-to-add message.
class ManageDiscountsAddSection extends StatelessWidget {
  final List<DiscountResponse> addable;
  final bool loadFailed;
  final Set<String> selectedToAdd;
  final ValueChanged<String> onToggle;

  const ManageDiscountsAddSection({
    super.key,
    required this.addable,
    required this.loadFailed,
    required this.selectedToAdd,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (loadFailed) {
      return const ManageDiscountsMessage(
        text: 'Couldn’t load discounts. Please try again.',
      );
    }
    if (addable.isEmpty) {
      return const ManageDiscountsMessage(
        text: 'No more discounts to add.',
        icon: Symbols.check_circle_sharp,
      );
    }
    final options = addable
        .map(
          (d) => DiscountOption(
            id: d.discountId,
            name: d.discountName,
            valueLabel: d.displayLabel,
            durationLabel: discountLifetimeLabel(d),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          'Add a discount',
          style: DesignConstants.h3.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        DiscountGrid(
          discounts: options,
          selectedIds: selectedToAdd,
          onToggle: (d) => onToggle(d.id),
        ),
      ],
    );
  }
}
