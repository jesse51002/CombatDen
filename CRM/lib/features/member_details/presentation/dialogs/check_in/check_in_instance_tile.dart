import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

final DateFormat _timeFormat = DateFormat.jm();
final DateFormat _dateFormat = DateFormat('EEE, MMM d');

/// One pickable class occurrence in the member check-in dialog: the class name
/// over its resolved start time + date, highlighted when [selected]. Dates and
/// times are already gym-local — rendered as given, no timezone math.
class CheckInInstanceTile extends StatelessWidget {
  final EffectiveClassInstance instance;
  final bool selected;
  final VoidCallback onTap;

  const CheckInInstanceTile({
    super.key,
    required this.instance,
    required this.selected,
    required this.onTap,
  });

  /// `6:00 PM` from a `HH:MM:SS` local time. The anchor date is arbitrary
  /// (formatting only) — no timezone is applied.
  String get _timeLabel {
    final parts = instance.resolvedClassTime.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return _timeFormat.format(DateTime(2000, 1, 1, hour, minute));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
        decoration: BoxDecoration(
          color: selected
              ? DesignConstants.primaryColor10
              : DesignConstants.backgroundColor,
          border: Border.all(
            color: selected
                ? DesignConstants.primaryColor
                : DesignConstants.divider,
          ),
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Text(
                    instance.className,
                    style: DesignConstants.pSemibold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$_timeLabel · ${_dateFormat.format(instance.classDate)}',
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text2nd,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Symbols.check_circle_sharp,
                size: DesignConstants.iconSizeMedium,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.primaryColor,
              ),
          ],
        ),
      ),
    );
  }
}
