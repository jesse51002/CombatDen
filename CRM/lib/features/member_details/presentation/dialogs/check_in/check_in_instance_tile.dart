import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// One pickable class occurrence in the member check-in dialog: the class name
/// over its resolved start time + date, highlighted when [selected]. Dates and
/// times are already gym-local — rendered as given, no timezone math.
///
/// [showClassName] is off in the class-scoped occurrence steps (the class was
/// just picked, so every tile is the same class) — the date/time becomes the
/// tile's primary line. It stays on in the mixed current-classes list.
class CheckInInstanceTile extends StatelessWidget {
  final EffectiveClassInstance instance;
  final bool selected;
  final bool showClassName;
  final VoidCallback onTap;

  const CheckInInstanceTile({
    super.key,
    required this.instance,
    required this.selected,
    this.showClassName = true,
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
                  if (showClassName)
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
                    style: showClassName
                        ? DesignConstants.h3Regular.copyWith(
                            color: DesignConstants.text2nd,
                          )
                        : DesignConstants.h2Regular,
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
