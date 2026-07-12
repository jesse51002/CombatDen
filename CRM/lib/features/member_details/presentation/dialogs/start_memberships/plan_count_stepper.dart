import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Quantity stepper for a checked one_time / trial plan.
/// The count multiplies the displayed class allowance and is
/// sent as the wire item's `quantity` (ONE item, not N copies)
/// when the request is built. No upper cap.
class PlanCountStepper extends StatelessWidget {
  final int count;
  final ValueChanged<int> onChanged;

  const PlanCountStepper({
    super.key,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        _StepButton(
          icon: Symbols.remove_sharp,
          onPressed: count > 1
              ? () => onChanged(count - 1)
              : null,
        ),
        Text('$count', style: DesignConstants.h3),
        _StepButton(
          icon: Symbols.add_sharp,
          onPressed: () => onChanged(count + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // IconButton keeps a >=48px (kMinInteractiveDimension) tap target while
    // the bordered box stays compact, so the +/- is easy to hit on a busy
    // front-desk screen without dominating the card.
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
        ),
        side: BorderSide(
          color: enabled
              ? DesignConstants.text2nd
              : DesignConstants.divider,
        ),
      ),
      icon: Icon(
        icon,
        weight: DesignConstants.iconWeight,
        size: DesignConstants.iconSizeSmall,
        color: enabled
            ? DesignConstants.text
            : DesignConstants.text3rd,
      ),
    );
  }
}
