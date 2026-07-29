import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_meta.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_tap.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_thumb.dart';

const double _kCardAspect = 4 / 3;

/// `ClassItemLayout.card` — a grid cell.
///
/// Raised surface, 4:3 image on top, meta padded beneath. Sized by the
/// column it lands in rather than by the screen, so it is the only
/// treatment that has to survive a half-width measure.
class ClassItemCard extends StatelessWidget {
  const ClassItemCard({
    super.key,
    required this.classData,
    required this.showBookings,
  });

  final MockClass classData;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return ClassItemTap(
      classData: classData,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClassItemThumb(
              imageUrl: classData.imageUrl,
              aspectRatio: _kCardAspect,
            ),
            Padding(
              padding: EdgeInsets.all(DesignConstants.spacingMedium),
              child: ClassItemMeta(
                classData: classData,
                showBookings: showBookings,
                tight: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
