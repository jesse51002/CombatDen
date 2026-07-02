import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Big period label — the visible week's date range (e.g.
/// "Jun 29, 2026 - Jul 5, 2026") — followed by previous/next chevron buttons
/// that move the board a week at a time. Top-left of the schedule header.
class MonthNavigator extends StatelessWidget {
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const MonthNavigator({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          label,
          style: DesignConstants.big2,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            _ChevronButton(
              icon: Symbols.chevron_left_sharp,
              onTap: onPrevious,
            ),
            _ChevronButton(
              icon: Symbols.chevron_right_sharp,
              onTap: onNext,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChevronButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ChevronButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        child: Icon(
          icon,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
          color: DesignConstants.text,
        ),
      ),
    );
  }
}
