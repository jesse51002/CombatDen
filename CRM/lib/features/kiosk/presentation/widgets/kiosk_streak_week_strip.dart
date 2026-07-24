import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Monday-first day labels for the week strip:
/// Mon Tue Wed Thu Fri Sat Sun.
const List<String> _kWeekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// A week with no attendance — the fall-back when the passed list is not the
/// expected length of seven, so a degraded response never indexes out of range.
const List<bool> _kAllOpen = [
  false,
  false,
  false,
  false,
  false,
  false,
  false,
];

/// A static, un-animated re-skin of the member app's streak week strip
/// (`StreakWeekStrip` in `lib/showcase/`), rebuilt against `DesignConstants`
/// for the kiosk glance: seven equal day badges, Monday→Sunday. A completed
/// day fills with the brand accent-soft wash + a sapphire check; an open day
/// sits on the muted ground with an open ring.
///
/// [daysCompleted] holds seven booleans, index 0 = Monday … 6 = Sunday — the
/// check-in response's `current_week_days` (already Monday-first). Rendered
/// **positionally with no reordering**. If it isn't exactly seven long the
/// strip falls back to all-open (never indexes out of range).
class KioskStreakWeekStrip extends StatelessWidget {
  final List<bool> daysCompleted;

  const KioskStreakWeekStrip({super.key, required this.daysCompleted});

  @override
  Widget build(BuildContext context) {
    final days = daysCompleted.length == _kWeekLabels.length
        ? daysCompleted
        : _kAllOpen;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: DesignConstants.kioskGlanceMeasure,
      ),
      child: Row(
        spacing: DesignConstants.spacingSmall,
        children: [
          for (var i = 0; i < _kWeekLabels.length; i++)
            Expanded(
              child: _DayBadge(
                label: _kWeekLabels[i],
                completed: days[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayBadge extends StatelessWidget {
  final String label;
  final bool completed;

  const _DayBadge({required this.label, required this.completed});

  @override
  Widget build(BuildContext context) {
    // The day LETTER is text: it holds the kiosk's AA contrast token. The dash
    // glyph under it is decoration, so it keeps the quieter tint — that
    // difference is what makes a missed day read as absent rather than as a
    // second label.
    final labelColor =
        completed ? DesignConstants.primaryColor : DesignConstants.text2nd;
    final iconColor =
        completed ? DesignConstants.primaryColor : DesignConstants.text3rd;
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: DesignConstants.spacingMedium,
        horizontal: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: completed
            ? DesignConstants.accentSoft
            : DesignConstants.backgroundAlt,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            label,
            style: DesignConstants.kioskLabel.copyWith(color: labelColor),
          ),
          Icon(
            completed ? Symbols.check_circle_sharp : Symbols.circle_sharp,
            weight: DesignConstants.iconWeight,
            color: iconColor,
            size: DesignConstants.iconSizeMedium,
          ),
        ],
      ),
    );
  }
}
