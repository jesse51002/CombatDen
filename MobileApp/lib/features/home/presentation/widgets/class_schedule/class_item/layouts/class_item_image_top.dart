import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_meta.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_tap.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_thumb.dart';

const double _kMediaAspect = 16 / 9;

/// `ClassItemLayout.imageTop` — a wide media card.
///
/// The image leads at full column width, meta reads beneath it. Costs
/// the most vertical space per class, which is why it is paired with the
/// day pager, where only one day is on screen at a time.
class ClassItemImageTop extends StatelessWidget {
  const ClassItemImageTop({
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
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.screenHorizontalPadding,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            ClassItemThumb(
              imageUrl: classData.imageUrl,
              aspectRatio: _kMediaAspect,
              borderRadius: DesignConstants.radiusSmall,
            ),
            ClassItemMeta(
              classData: classData,
              showBookings: showBookings,
            ),
          ],
        ),
      ),
    );
  }
}
