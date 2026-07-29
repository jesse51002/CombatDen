import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';
import 'package:mobile_app/features/home/presentation/widgets/class_schedule/class_item/class_item_time.dart';

/// The text column of a class row: title, time, instructor, attendee
/// count, and the booked mark. Identical in every [ClassItemLayout].
class ClassItemMeta extends StatelessWidget {
  const ClassItemMeta({
    super.key,
    required this.classData,
    required this.showBookings,
    this.tight = false,
    this.showTime = true,
  });

  final MockClass classData;
  final bool showBookings;

  /// Tightens the internal gaps for the dense and card treatments.
  final bool tight;

  /// False only where the layout hoists [ClassItemTime] into its own
  /// gutter (the spine) — the time moves, it is never dropped.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tight
          ? DesignConstants.spacingSmall
          : DesignConstants.spacingMedium,
      children: [
        Text(classData.name, style: DesignConstants.h3),
        if (showTime) ClassItemTime(classData: classData),
        Text(
          classData.mentor,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        if (classData.attending != null)
          _Attendees(count: classData.attending!),
        if (showBookings && classData.isBooked) const _BookedMark(),
      ],
    );
  }
}

class _BookedMark extends StatelessWidget {
  const _BookedMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.check_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text,
          size: DesignConstants.iconSizeXs,
        ),
        Flexible(
          child: Text('You booked this class!', style: DesignConstants.h3),
        ),
      ],
    );
  }
}

class _Attendees extends StatelessWidget {
  const _Attendees({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.person_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text2nd,
          size: DesignConstants.iconSizeXs,
        ),
        Flexible(
          child: Text(
            '$count attending',
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        ),
      ],
    );
  }
}
