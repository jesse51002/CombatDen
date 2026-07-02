import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

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
                    style: DesignConstants.h2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    classDateTimeLabel(
                      instance.classDate,
                      instance.resolvedClassTime,
                    ),
                    style: DesignConstants.h3Regular.copyWith(
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
