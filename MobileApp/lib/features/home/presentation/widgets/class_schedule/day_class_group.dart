import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_group/day_group_grid.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/day_group/day_group_list.dart';

/// One day of the schedule: its date band, then that day's classes.
///
/// Every home format renders these — the band and the classes are the
/// day, not a variant. [grid] and [itemLayout] pick how the classes are
/// arranged beneath the band.
class DayClassGroup extends StatelessWidget {
  const DayClassGroup({
    super.key,
    required this.day,
    this.showBookings = true,
    this.itemLayout = ClassItemLayout.textLeftThumbRight,
    this.grid = false,
  });

  final MockDay day;
  final bool showBookings;
  final ClassItemLayout itemLayout;

  /// Two-up cards instead of a stack. [itemLayout] is ignored — the grid
  /// owns its cell treatment.
  final bool grid;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingBig),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.screenHorizontalPadding,
            ),
            child: Text(
              day.label.toUpperCase(),
              style: DesignConstants.h2Bold,
            ),
          ),
          if (grid)
            DayGroupGrid(day: day, showBookings: showBookings)
          else
            DayGroupList(
              day: day,
              showBookings: showBookings,
              itemLayout: itemLayout,
            ),
        ],
      ),
    );
  }
}
