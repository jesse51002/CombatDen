import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/cart_policy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';

/// How many of one plan a picked membership stacks — three class packs bought
/// together as one line.
///
/// The FLOOR is 1 and it is enforced here, not by the caller: zero is not a
/// quantity, it is a removal, and removal is the card's own trash control.
/// Both bounds come from the surface's [CartPolicy], so a surface that sells
/// one unit at a time never renders this at all
/// ([CartPolicy.offersQuantity]) — it is absent rather than disabled, which is
/// the same rule the whole config follows.
class FlowQuantityStepper extends StatelessWidget {
  final int units;

  /// The units the surface will accept, already clamped by the host through
  /// [CartPolicy.clampQuantity].
  final ValueChanged<int> onChanged;

  final CartPolicy cart;

  /// The word for what is being counted — `Packs`. Passed in because only the
  /// host knows what one unit of this plan is.
  final String label;

  /// The screen-reader labels on the two buttons, which have no visible words.
  final String decrementSemanticLabel;
  final String incrementSemanticLabel;

  const FlowQuantityStepper({
    super.key,
    required this.units,
    required this.onChanged,
    required this.cart,
    required this.label,
    required this.decrementSemanticLabel,
    required this.incrementSemanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final ceiling = cart.maxQuantity;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: scale.label),
        _Step(
          icon: Symbols.remove_sharp,
          semanticLabel: decrementSemanticLabel,
          onTap: units > 1 ? () => onChanged(cart.clampQuantity(units - 1)) : null,
        ),
        Text('$units', style: scale.name),
        _Step(
          icon: Symbols.add_sharp,
          semanticLabel: incrementSemanticLabel,
          onTap: ceiling != null && units >= ceiling
              ? null
              : () => onChanged(cart.clampQuantity(units + 1)),
        ),
      ],
    );
  }
}

/// One end of the stepper. Disabled rather than absent: the pair has to stay
/// the same shape at every count, or the control moves under a finger.
class _Step extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  const _Step({
    required this.icon,
    required this.semanticLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final live = onTap != null;
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: live,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.spacingMedium),
          decoration: BoxDecoration(
            color: DesignConstants.surface,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            border: Border.all(color: DesignConstants.line),
          ),
          child: Icon(
            icon,
            size: DesignConstants.iconSizeSmall,
            weight: DesignConstants.iconWeight,
            color: live ? DesignConstants.text : DesignConstants.text3rd,
          ),
        ),
      ),
    );
  }
}
