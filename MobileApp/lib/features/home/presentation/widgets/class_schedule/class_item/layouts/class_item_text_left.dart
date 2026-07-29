import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_meta.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_rule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_tap.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_thumb.dart';

const double _kThumbWidth = 122;
const double _kThumbHeight = 73;

/// `ClassItemLayout.textLeftThumbRight` — the row that ships today.
///
/// Meta column left, small 16:9 thumbnail right, rule beneath. Value for
/// value the previous `ClassListItem` rendering, so a tenant with no
/// layout slot sees no change.
class ClassItemTextLeft extends StatelessWidget {
  const ClassItemTextLeft({
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
      spacing: DesignConstants.spacingLarge,
      children: [
        ClassItemTap(
          classData: classData,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
              vertical: DesignConstants.spacingMedium,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: DesignConstants.spacingLarge,
              children: [
                Expanded(
                  child: ClassItemMeta(
                    classData: classData,
                    showBookings: showBookings,
                  ),
                ),
                ClassItemThumb(
                  imageUrl: classData.imageUrl,
                  width: _kThumbWidth,
                  height: _kThumbHeight,
                  borderRadius: DesignConstants.radiusSmall,
                ),
              ],
            ),
          ),
        ),
        const ClassItemRule(),
      ],
    );
  }
}
