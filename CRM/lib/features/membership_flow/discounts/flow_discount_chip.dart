import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// One discount already on a membership — its name, and the × that takes it
/// off.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// GREEN, not sapphire: every other chip and pill in this flow marks a fact
/// about a person or a plan, and this one marks money coming OFF. It is the
/// same green the struck-through price beside it resolves to, so a member
/// looking at the card can follow "these three chips are why that number
/// dropped" without being told.
class FlowDiscountChip extends StatelessWidget {
  final String label;

  /// Take it off this membership. Null renders the chip as a plain read-only
  /// mark — the review lists what is applied without offering to change it.
  final VoidCallback? onRemove;

  /// The screen-reader label on the × — it names the discount AND the fact
  /// that removal is per-membership, because the same preset is usually on
  /// several cards at once.
  final String removeSemanticLabel;

  const FlowDiscountChip({
    super.key,
    required this.label,
    required this.removeSemanticLabel,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final remove = onRemove;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.greenDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Flexible(
            child: Text(
              label,
              style: scale.micro.copyWith(color: DesignConstants.goodGreen),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (remove != null)
            Semantics(
              label: removeSemanticLabel,
              button: true,
              excludeSemantics: true,
              child: InkWell(
                onTap: remove,
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
                child: Icon(
                  Symbols.close_sharp,
                  size: DesignConstants.iconSizeTiny,
                  weight: DesignConstants.iconWeight,
                  color: DesignConstants.goodGreen,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
