import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// The `+ Add discount` affordance that sits at the end of a membership's chip
/// row and unfolds the panel BELOW it.
///
/// **Staff-only** — see `discount_labels.dart`.
///
/// A dashed outline, which is this app's standing "there could be one more of
/// these here" mark (`DashedAddTile`, `MutedAddTile`). It is deliberately the
/// quietest control on the card: the sale is the membership, and a discount is
/// something staff reach for occasionally.
///
/// It carries [expanded] so it can say `aria-expanded` — the panel it opens is
/// in the same card rather than in a dialog, and a control that opens
/// something in place has to announce that it did.
class FlowDiscountAddButton extends StatelessWidget {
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  const FlowDiscountAddButton({
    super.key,
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.spacingMedium,
            vertical: DesignConstants.spacingSmall,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
            border: Border.all(color: DesignConstants.primaryColor50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Icon(
                expanded ? Symbols.remove_sharp : Symbols.add_sharp,
                size: DesignConstants.iconSizeTiny,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.primaryColor,
              ),
              Text(
                label,
                style: scale.micro.copyWith(
                  color: DesignConstants.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
