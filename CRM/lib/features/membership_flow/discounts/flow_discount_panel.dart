import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/discounts/discount_copy.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/discounts/flow_custom_discount_form.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_preset_list.dart';
import 'package:crm/features/membership_flow/discounts/flow_segmented.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_buttons.dart';

/// Where a discount comes from.
enum FlowDiscountSource {
  /// One of the gym's saved, reusable presets.
  presets(FlowDiscountCopy.presetsTab),

  /// A one-off built here, for this membership only.
  custom(FlowDiscountCopy.customTab);

  const FlowDiscountSource(this.label);

  final String label;
}

/// The discount picker, unfolded IN PLACE inside the membership card that
/// opened it.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// **Never a dialog.** The old wizard put this behind one, and that is exactly
/// what made discounts feel like a separate job from selling the membership —
/// which is how a whole step of the flow grew around them. Unfolding here
/// keeps the price, the plan and the discount on one screen, so the number
/// visibly moves while staff are still deciding.
///
/// It is stateless: WHICH tab is open and WHETHER it is open at all belong to
/// the card above it, because closing the panel and removing a chip are the
/// same card's state.
class FlowDiscountPanel extends StatelessWidget {
  /// The capability the host was given. A surface without one cannot build
  /// this widget at all — that is the whole no-discounts mechanism.
  final DiscountsCapability discounts;

  /// Preset ids already on THIS membership.
  final Set<String> addedPresetIds;

  final FlowDiscountSource source;
  final ValueChanged<FlowDiscountSource> onSourceChanged;

  final ValueChanged<String> onAddPreset;
  final ValueChanged<DiscountValue> onAddCustom;

  /// Fold the panel away. It commits nothing — every pick applied when it was
  /// made — which is why it reads as "done" rather than "save".
  final VoidCallback onClose;

  const FlowDiscountPanel({
    super.key,
    required this.discounts,
    required this.addedPresetIds,
    required this.source,
    required this.onSourceChanged,
    required this.onAddPreset,
    required this.onAddCustom,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingLarge),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        border: Border.all(color: DesignConstants.primaryColor25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          _Head(
            source: source,
            onSourceChanged: onSourceChanged,
            onClose: onClose,
          ),
          if (source == FlowDiscountSource.presets)
            FlowDiscountPresetList(
              presets: discounts.offerablePresets,
              addedIds: addedPresetIds,
              onAdd: onAddPreset,
            )
          else
            FlowCustomDiscountForm(
              onAdd: onAddCustom,
              onCancel: onClose,
            ),
        ],
      ),
    );
  }
}

/// The source tabs, and the way out.
///
/// The close sits beside the PRESET list only: the custom form has its own
/// Cancel, and two ways to abandon the same form on one row is one too many.
class _Head extends StatelessWidget {
  final FlowDiscountSource source;
  final ValueChanged<FlowDiscountSource> onSourceChanged;
  final VoidCallback onClose;

  const _Head({
    required this.source,
    required this.onSourceChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FlowSegmented<FlowDiscountSource>(
              options: FlowDiscountSource.values,
              value: source,
              labelOf: (option) => option.label,
              onChanged: onSourceChanged,
              loud: true,
            ),
          ),
        ),
        if (source == FlowDiscountSource.presets)
          FlowOutlineButton(
            text: FlowDiscountCopy.closePanel,
            onPressed: onClose,
          ),
      ],
    );
  }
}
