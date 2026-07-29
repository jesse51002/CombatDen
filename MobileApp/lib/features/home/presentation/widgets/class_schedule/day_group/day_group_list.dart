import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_list_item.dart';

/// A day's classes stacked one per row — the shipped arrangement, and
/// what every format except `boardGrid` uses. The row treatment is the
/// format's choice; the stack is not.
class DayGroupList extends StatelessWidget {
  const DayGroupList({
    super.key,
    required this.day,
    required this.showBookings,
    required this.itemLayout,
  });

  final MockDay day;
  final bool showBookings;
  final ClassItemLayout itemLayout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final c in day.classes)
          ClassListItem(
            classData: c,
            showBookings: showBookings,
            layout: itemLayout,
          ),
      ],
    );
  }
}
