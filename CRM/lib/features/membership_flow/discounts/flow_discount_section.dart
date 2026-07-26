import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/discount_value.dart';
import 'package:crm/features/membership_flow/discounts/discount_copy.dart';
import 'package:crm/features/membership_flow/discounts/discounts_capability.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_add_button.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_chip.dart';
import 'package:crm/features/membership_flow/discounts/flow_discount_panel.dart';

/// ONE membership's discounts, as they sit on its card: the chips already
/// applied, the affordance that adds another, and the panel that unfolds in
/// place beneath them.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// This is the whole reason the wizard's separate discounts step disappears.
/// Discounts attach per MEMBERSHIP, never per member — which is what the
/// backend has always modelled — so two picked plans mean two of these, each
/// owning its own set, and the model is legible without being explained.
///
/// It owns exactly two pieces of state, both of which are about this card and
/// nothing else: whether its panel is open, and which tab that panel is on.
/// Everything that CHANGES the sale leaves as a callback — the host holds the
/// draft, because the draft is what gets sent.
class FlowDiscountSection extends StatefulWidget {
  /// The capability the host was given. A surface without one cannot build
  /// this widget at all.
  final DiscountsCapability discounts;

  /// Preset ids on this membership, in pick order.
  final Set<String> presetIds;

  /// One-off values built here for this membership, in pick order.
  final List<DiscountValue> customs;

  final ValueChanged<String> onAddPreset;
  final ValueChanged<DiscountValue> onAddCustom;

  /// Take one off this membership — and only this one. The same preset is
  /// usually on several cards at once.
  final ValueChanged<FlowDiscountReference> onRemove;

  const FlowDiscountSection({
    super.key,
    required this.discounts,
    required this.presetIds,
    required this.customs,
    required this.onAddPreset,
    required this.onAddCustom,
    required this.onRemove,
  });

  @override
  State<FlowDiscountSection> createState() => _FlowDiscountSectionState();
}

class _FlowDiscountSectionState extends State<FlowDiscountSection> {
  bool _open = false;
  FlowDiscountSource _source = FlowDiscountSource.presets;

  /// A gym with no saved presets opens straight onto the form it can actually
  /// use. The presets tab still exists and still explains itself — this only
  /// saves a tap that has one possible outcome.
  void _toggle() {
    setState(() {
      _open = !_open;
      if (_open && !widget.discounts.hasOfferablePresets) {
        _source = FlowDiscountSource.custom;
      }
    });
  }

  /// Adding a custom folds the panel: the chip that just appeared above is the
  /// confirmation, and leaving a filled-in form open invites adding it twice.
  void _addCustom(DiscountValue value) {
    widget.onAddCustom(value);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final applied = widget.discounts.appliedFor(
      presetIds: widget.presetIds,
      customs: widget.customs,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Wrap(
          spacing: DesignConstants.spacingMedium,
          runSpacing: DesignConstants.spacingMedium,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final discount in applied)
              FlowDiscountChip(
                label: discount.label,
                removeSemanticLabel:
                    FlowDiscountCopy.removeSemantic(discount.label),
                onRemove: () => widget.onRemove(discount.reference),
              ),
            FlowDiscountAddButton(
              label: FlowDiscountCopy.addDiscount,
              expanded: _open,
              onTap: _toggle,
            ),
          ],
        ),
        if (_open)
          FlowDiscountPanel(
            discounts: widget.discounts,
            addedPresetIds: widget.presetIds,
            source: _source,
            onSourceChanged: (value) => setState(() => _source = value),
            onAddPreset: widget.onAddPreset,
            onAddCustom: _addCustom,
            onClose: () => setState(() => _open = false),
          ),
      ],
    );
  }
}
