import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/class_detail_args.dart';
import 'package:mobile_app/features/home/bloc/home_bloc.dart';
import 'package:mobile_app/features/home/bloc/home_event.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';

/// One occurrence row on the schedule board. Taps open the class detail with
/// the occurrence + its booked state; on return the home board refetches
/// (a reservation may have changed).
class ClassListItem extends StatelessWidget {
  const ClassListItem({
    super.key,
    required this.occurrence,
    required this.booked,
  });

  final ClassOccurrence occurrence;
  final bool booked;

  void _openDetail(BuildContext context) {
    final homeBloc = context.read<HomeBloc>();
    Navigator.of(context).pushNamed(
      AppRoutes.classDetail,
      arguments: ClassDetailArgs(occurrence: occurrence, booked: booked),
    ).then((_) {
      if (!homeBloc.isClosed) homeBloc.add(const HomeRefreshRequested());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        InkWell(
          onTap: () => _openDetail(context),
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
                  child: _ClassInfo(occurrence: occurrence, booked: booked),
                ),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(DesignConstants.radiusSmall),
                  child: Image(
                    image: CachedNetworkImageProvider(occurrence.imageUrl),
                    width: 122,
                    height: 73,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: 122,
                      height: 73,
                      child: ColoredBox(color: DesignConstants.card),
                    ),
                  ),
                ),
              ],
            ),
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
  const _ClassInfo({required this.occurrence, required this.booked});

  final ClassOccurrence occurrence;
  final bool booked;

  @override
  Widget build(BuildContext context) {
    final range = formatSlotRange(
      occurrence.resolvedClassTime,
      occurrence.resolvedDurationMinutes,
    );
    final mentor = occurrence.resolvedInstructorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(occurrence.className, style: DesignConstants.h3),
        Text(
          '$range (${occurrence.resolvedDurationMinutes} min)',
          style: DesignConstants.p,
        ),
        if (mentor != null && mentor.isNotEmpty)
          Text(
            mentor,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        _AttendingCount(count: occurrence.signupCount),
        if (booked) const _BookedConfirmation(),
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
          size: DesignConstants.iconSizeXs,
        ),
        Text('You booked this class!', style: DesignConstants.h3),
      ],
    );
  }
}

class _AttendingCount extends StatelessWidget {
  const _AttendingCount({required this.count});
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
        Text(
          '$count attending',
          style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
