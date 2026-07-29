import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_meta.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_rule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_tap.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_thumb.dart';

const double _kThumbSize = 44;

/// `ClassItemLayout.dense` — the compact row.
///
/// Small square thumbnail leading, tight meta, hairline rule. Fits the
/// most classes under a hero without the list turning into a wall.
///
/// The docs' `nextUpHero` sketch drops the thumbnail here. It stays:
/// dropping it would remove an element from the screen, which is the one
/// thing a layout format may never do.
class ClassItemDense extends StatelessWidget {
  const ClassItemDense({
    super.key,
    required this.classData,
    required this.showBookings,
  });

  final MockClass classData;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        ClassItemTap(
          classData: classData,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
              vertical: DesignConstants.spacingSmall,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: DesignConstants.spacingMedium,
              children: [
                ClassItemThumb(
                  imageUrl: classData.imageUrl,
                  width: _kThumbSize,
                  height: _kThumbSize,
                  borderRadius: DesignConstants.radiusSmall,
                ),
                Expanded(
                  child: ClassItemMeta(
                    classData: classData,
                    showBookings: showBookings,
                    tight: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        const ClassItemRule(hairline: true),
      ],
    );
  }
}
