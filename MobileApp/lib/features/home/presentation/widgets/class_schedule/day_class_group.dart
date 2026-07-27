import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/models/schedule_day.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_list_item.dart';

/// One day's block on the schedule board: the day heading plus its
/// occurrences — or a quiet empty-day state when the gym has no classes that
/// day.
class DayClassGroup extends StatelessWidget {
  const DayClassGroup({
    super.key,
    required this.day,
    required this.bookedKeys,
  });

  final ScheduleDay day;

  /// Slot keys the member has reserved — an occurrence renders its booked
  /// confirmation when its key is in here.
  final Set<String> bookedKeys;

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
          if (day.occurrences.isEmpty)
            const _EmptyDay()
          else
            ...day.occurrences.map(
              (o) => ClassListItem(
                occurrence: o,
                booked: bookedKeys.contains(o.slotKey),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: Text(
        'No classes scheduled.',
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}
