import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_layout.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_list_item.dart';

const int _kColumns = 2;

/// A day's classes as a two-up card grid.
///
/// Hand-paired rows rather than a `GridView`: the group is already
/// inside a lazy sliver, and pairing keeps each row's two cards the same
/// height without a second scroll view or a fixed cell extent.
class DayGroupGrid extends StatelessWidget {
  const DayGroupGrid({
    super.key,
    required this.day,
    required this.showBookings,
  });

  final MockDay day;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          for (var i = 0; i < day.classes.length; i += _kColumns)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DesignConstants.spacingLarge,
                children: [
                  for (var c = 0; c < _kColumns; c++)
                    Expanded(
                      child: i + c < day.classes.length
                          ? ClassListItem(
                              classData: day.classes[i + c],
                              showBookings: showBookings,
                              layout: ClassItemLayout.card,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
