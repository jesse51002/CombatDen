import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

class ClassListItem extends StatelessWidget {
  const ClassListItem({
    super.key,
    required this.classData,
    this.showBookings = true,
  });

  final MockClass classData;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignConstants.screenHorizontalPadding,
            vertical: DesignConstants.spacingMedium,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                child: _ClassInfo(
                  classData: classData,
                  showBookings: showBookings,
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  DesignConstants.radiusSmall,
                ),
                child: Image.asset(
                  classData.imageAsset,
                  width: 122,
                  height: 73,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: DesignConstants.buttonBorder,
          color: DesignConstants.divider,
        ),
      ],
    );
  }

}

class _ClassInfo extends StatelessWidget {
  const _ClassInfo({required this.classData, required this.showBookings});
  final MockClass classData;
  final bool showBookings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(classData.name, style: DesignConstants.h3),
        Text(
          '${classData.timeRange} (${classData.durationMinutes} min)',
          style: DesignConstants.p,
        ),
        Text(
          classData.mentor,
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
        if (classData.attending != null) _BookedCount(count: classData.attending!),
        if (showBookings && classData.isBooked) const _BookedConfirmation(),
      ],
    );
  }
}

class _BookedConfirmation extends StatelessWidget {
  const _BookedConfirmation();

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
          size: 16,
        ),
        Text('You booked this class!', style: DesignConstants.h3),
      ],
    );
  }
}

class _BookedCount extends StatelessWidget {
  const _BookedCount({required this.count});
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
          size: 16,
        ),
        Text(
          '$count attending',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
