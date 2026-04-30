import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_list_item.dart';

class DayClassGroup extends StatelessWidget {
  const DayClassGroup({
    super.key,
    required this.day,
    this.showBookings = true,
  });

  final MockDay day;
  final bool showBookings;

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
          ...day.classes.map(
            (c) => ClassListItem(classData: c, showBookings: showBookings),
          ),
        ],
      ),
    );
  }
}
