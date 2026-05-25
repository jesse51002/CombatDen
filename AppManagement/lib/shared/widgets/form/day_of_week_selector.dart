import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Multi-select day-of-week toggles. Day indices are 0 = Sunday ..
/// 6 = Saturday, matching the `sun..sat` flags on `gym_classes`.
class DayOfWeekSelector extends StatelessWidget {
  final Set<int> selectedDays;
  final ValueChanged<int> onToggle;

  static const List<String> _labels = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
  ];

  const DayOfWeekSelector({
    super.key,
    required this.selectedDays,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignConstants.spacingMedium,
      runSpacing: DesignConstants.spacingMedium,
      children: [
        for (var i = 0; i < _labels.length; i++)
          _DayChip(
            label: _labels[i],
            selected: selectedDays.contains(i),
            onTap: () => onToggle(i),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        decoration: BoxDecoration(
          color: selected ? DesignConstants.primaryColor : DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.text2nd,
            width: DesignConstants.buttonBorder,
          ),
        ),
        child: Text(
          label,
          style: DesignConstants.p.copyWith(
            color: selected ? DesignConstants.text : DesignConstants.text2nd,
          ),
        ),
      ),
    );
  }
}
