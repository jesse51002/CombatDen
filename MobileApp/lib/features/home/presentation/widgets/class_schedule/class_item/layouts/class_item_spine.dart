import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_meta.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_tap.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_thumb.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_time.dart';

const double _kGutterWidth = 66;
const double _kAvatarSize = 44;

/// `ClassItemLayout.spine` — the class hangs off its own start time.
///
/// The time moves out of the meta column into a leading gutter, and a
/// vertical rule runs the full height of every row so consecutive
/// classes read as one continuous timetable. The thumbnail demotes to a
/// small square so the time column keeps the eye.
class ClassItemSpine extends StatelessWidget {
  const ClassItemSpine({
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
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingLarge,
            children: [
              SizedBox(
                width: _kGutterWidth,
                child: ClassItemTime(classData: classData, stacked: true),
              ),
              Container(
                width: DesignConstants.dividerThickness,
                color: DesignConstants.divider,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: DesignConstants.spacingMedium,
                  ),
                  child: ClassItemMeta(
                    classData: classData,
                    showBookings: showBookings,
                    showTime: false,
                    tight: true,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ClassItemThumb(
                  imageUrl: classData.imageUrl,
                  width: _kAvatarSize,
                  height: _kAvatarSize,
                  borderRadius: DesignConstants.radiusSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
