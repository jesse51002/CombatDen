import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_response.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/discounts/discount_copy.dart';
import 'package:crm/features/membership_flow/discounts/discount_labels.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_preset_row.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// The gym's saved discounts, as a list one of which can be added to this
/// membership.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// A LIST, never a grid: every row has to show its lifetime beside its value,
/// and a grid cell has room for one of the two (see [FlowDiscountPresetRow]).
///
/// A gym with no saved presets still gets the custom form on the other tab, so
/// the empty state names that route instead of dead-ending. The footnote below
/// the list is the other half of that: `custom`-typed rows are one-offs
/// already minted for somebody else's membership and are never offered here,
/// and the panel SAYS so rather than quietly showing a shorter list than the
/// discounts page does.
class FlowDiscountPresetList extends StatelessWidget {
  /// Already filtered to what may be offered
  /// (`DiscountsCapability.offerablePresets`).
  final List<DiscountResponse> presets;

  /// Preset ids already on this membership — they render selected and inert.
  final Set<String> addedIds;

  final ValueChanged<String> onAdd;

  const FlowDiscountPresetList({
    super.key,
    required this.presets,
    required this.addedIds,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    if (presets.isEmpty) {
      return const EmptyState(
        icon: Symbols.sell_sharp,
        title: FlowDiscountCopy.noPresetsTitle,
        body: FlowDiscountCopy.noPresetsBody,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final preset in presets)
          FlowDiscountPresetRow(
            name: preset.discountName,
            lifetimeLabel: flowDiscountLifetimeLabel(preset.value),
            valueLabel: flowDiscountValueLabel(preset.value),
            added: addedIds.contains(preset.discountId),
            addedLabel: FlowDiscountCopy.added,
            onTap: () => onAdd(preset.discountId),
          ),
        Text(
          FlowDiscountCopy.presetsFootnote,
          style: scale.caption.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
