import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Big month label (e.g. "February, 2026") followed by previous/next
/// chevron buttons. Used at the top of the schedule above the grid.
class MonthNavigator extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const MonthNavigator({
    super.key,
    required this.monthLabel,
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
          monthLabel,
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
