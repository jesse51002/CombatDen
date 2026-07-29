import 'package:flutter/material.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/layouts/class_item_card.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/layouts/class_item_dense.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/layouts/class_item_image_top.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/layouts/class_item_spine.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/layouts/class_item_text_left.dart';

/// One class in the schedule.
///
/// The DATA props are fixed — every home format hands this the same
/// [classData] and the same [showBookings]. [layout] is presentation
/// only: it picks which of the treatments in `class_item/layouts/` draws
/// the row, and each of those renders the identical element set.
class ClassListItem extends StatelessWidget {
  const ClassListItem({
    super.key,
    required this.classData,
    this.showBookings = true,
    this.layout = ClassItemLayout.textLeftThumbRight,
  });

  final MockClass classData;
  final bool showBookings;
  final ClassItemLayout layout;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      ClassItemLayout.textLeftThumbRight => ClassItemTextLeft(
        classData: classData,
        showBookings: showBookings,
      ),
      ClassItemLayout.imageTop => ClassItemImageTop(
        classData: classData,
        showBookings: showBookings,
      ),
      ClassItemLayout.spine => ClassItemSpine(
        classData: classData,
        showBookings: showBookings,
      ),
      ClassItemLayout.dense => ClassItemDense(
        classData: classData,
        showBookings: showBookings,
      ),
      ClassItemLayout.card => ClassItemCard(
        classData: classData,
        showBookings: showBookings,
      ),
    };
  }
}
