import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Quantity stepper for a checked one_time / trial plan.
/// The count multiplies the displayed class allowance and
/// maps to N identical wire items (N copies of the pack) when
/// the request is built. No upper cap.
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
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(
        DesignConstants.radiusSmall,
      ),
      child: Container(
        padding: const EdgeInsets.all(
          DesignConstants.spacingTiny,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            DesignConstants.radiusSmall,
          ),
          border: Border.all(
            color: enabled
                ? DesignConstants.text2nd
                : DesignConstants.divider,
          ),
        ),
        child: Icon(
          icon,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeSmall,
          color: enabled
              ? DesignConstants.text
              : DesignConstants.text3rd,
        ),
      ),
    );
  }
}
