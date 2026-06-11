import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Quantity stepper for a checked one_time / trial plan.
/// The count multiplies the displayed class allowance.
///
// TODO(known placeholder): increment is disabled ("coming
// soon") — the backend rejects duplicate (member, price)
// items until PaymentRefactor.md §10 ships, so the count is
// capped at 1 for submission. DELETE this comment (and
// enable increment) when §10 lands and count N maps to N
// duplicate items.
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
        Tooltip(
          message: 'Multiple purchases per run are '
              'coming soon',
          child: _StepButton(
            icon: Symbols.add_sharp,
            // Capped at 1 until duplicates are accepted
            // (PaymentRefactor.md §10) — see the class
            // comment.
            onPressed: null,
          ),
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
