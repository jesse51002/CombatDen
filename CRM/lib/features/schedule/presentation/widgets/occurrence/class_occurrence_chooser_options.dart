import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';

final DateFormat _dateLabel = DateFormat('EEEE, MMM d, yyyy');

/// The two tappable choices inside [ClassOccurrenceChooserDialog]'s body:
/// "This occurrence" (the occurrence-edit screen) or "All future occurrences"
/// (the class definition editor). Shows the tapped [occurrenceDate] so staff
/// can confirm which day they're about to manage.
class ClassOccurrenceChooserOptions extends StatelessWidget {
  final DateTime occurrenceDate;
  final VoidCallback onThisOccurrence;
  final VoidCallback onAllFuture;

  const ClassOccurrenceChooserOptions({
    super.key,
    required this.occurrenceDate,
    required this.onThisOccurrence,
    required this.onAllFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          _dateLabel.format(occurrenceDate),
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        _ChooserOption(
          icon: Symbols.event_sharp,
          title: 'This occurrence',
          subtitle: 'Edit just this day — instructor, time, capacity, '
              'attendance.',
          onTap: onThisOccurrence,
        ),
        _ChooserOption(
          icon: Symbols.event_repeat_sharp,
          title: 'All future occurrences',
          subtitle: 'Edit the recurring class — name, schedule, '
              'instructors, capacity.',
          onTap: onAllFuture,
        ),
      ],
    );
  }
}

/// One tappable row in the chooser: icon, title, subtitle, and a chevron.
class _ChooserOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChooserOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          color: DesignConstants.backgroundColor,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          border: Border.all(color: DesignConstants.divider),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              icon,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeLarge,
              color: DesignConstants.primaryColor,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(title, style: DesignConstants.h3),
                  Text(
                    subtitle,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Symbols.chevron_right_sharp,
              weight: DesignConstants.iconWeight,
              size: DesignConstants.iconSizeMedium,
              color: DesignConstants.text2nd,
            ),
          ],
        ),
      ),
    );
  }
}
