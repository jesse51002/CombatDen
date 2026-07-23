import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Sunday-first day labels for the week strip (mockup `.week-strip`).
const List<String> _kWeekLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// A static, un-animated re-skin of the member app's streak week strip
/// (`StreakWeekStrip` in `lib/showcase/`), rebuilt against `DesignConstants`
/// for the kiosk glance: seven equal day badges, Sunday→Saturday. A completed
/// day fills with the brand accent-soft wash + a sapphire check; an open day
/// sits on the muted ground with an open ring.
///
/// [daysCompleted] must hold exactly seven booleans (Sun..Sat). On the kiosk
/// today's checked-in day is the only one marked done — the backend exposes no
/// per-day completion source (see the glance screen's data note).
class KioskStreakWeekStrip extends StatelessWidget {
  final List<bool> daysCompleted;

  const KioskStreakWeekStrip({super.key, required this.daysCompleted});

  @override
  Widget build(BuildContext context) {
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
                completed: i < daysCompleted.length && daysCompleted[i],
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
          Text(label, style: DesignConstants.h2.copyWith(color: labelColor)),
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
