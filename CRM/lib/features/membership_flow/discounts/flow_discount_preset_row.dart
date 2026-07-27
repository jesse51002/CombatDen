import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// One of the gym's saved discounts, as a pickable row: its name, how long it
/// lasts, what comes off, and — once it is on this membership — an inert
/// `Added` mark.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// A ROW and not a tile in a grid, because the lifetime is the fact staff get
/// wrong: "20% off" and "20% off for one cycle" are different sales, and a
/// grid cell has room for one of the two. Laid out left-to-right in the order
/// the question is asked — which discount, for how long, how much.
///
/// An already-added preset renders selected and INERT rather than
/// disappearing: a list that silently shortens as you pick from it makes staff
/// hunt for something they just chose. Removal lives on the chip up on the
/// card, which is the thing that says what this membership actually has.
class FlowDiscountPresetRow extends StatelessWidget {
  final String name;

  /// How long it lasts — `Forever`, `3 cycles (3 months)`, `Until Nov 30,
  /// 2026`.
  final String lifetimeLabel;

  /// What comes off — `20% off`, `$15.00 off`.
  final String valueLabel;

  /// Already on this membership.
  final bool added;

  /// The word on the inert mark. Passed in so the row states no copy of its
  /// own.
  final String addedLabel;

  final VoidCallback onTap;

  const FlowDiscountPresetRow({
    super.key,
    required this.name,
    required this.lifetimeLabel,
    required this.valueLabel,
    required this.added,
    required this.addedLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Semantics(
      button: !added,
      selected: added,
      child: InkWell(
        onTap: added ? null : onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.spacingMedium,
            vertical: DesignConstants.spacingMedium,
          ),
          decoration: BoxDecoration(
            color: added ? DesignConstants.primaryColor10 : null,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            border: Border.all(
              color: added
                  ? DesignConstants.primaryColor
                  : DesignConstants.line,
            ),
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                added ? Symbols.check_sharp : Symbols.sell_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
                color: added
                    ? DesignConstants.primaryColor
                    : DesignConstants.text2nd,
              ),
              Expanded(
                child: Text(
                  name,
                  style: scale.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                lifetimeLabel,
                style: scale.caption.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
              Text(
                valueLabel,
                style: scale.label.copyWith(
                  color: DesignConstants.goodGreen,
                ),
              ),
              if (added) _AddedMark(label: addedLabel),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inert mark on a preset this membership already carries.
class _AddedMark extends StatelessWidget {
  final String label;

  const _AddedMark({required this.label});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.greenDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Text(
        label,
        style: scale.tag.copyWith(color: DesignConstants.goodGreen),
      ),
    );
  }
}
