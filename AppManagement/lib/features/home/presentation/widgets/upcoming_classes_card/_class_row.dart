import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/home/data/mock_upcoming_classes.dart';

/// One class within a day group — a left column of name/time/instructor
/// (with optional booked-count chip) and a right thumbnail. Tapping the
/// row drills into the schedule screen.
class ClassRow extends StatelessWidget {
  final ScheduledClass scheduledClass;

  const ClassRow({super.key, required this.scheduledClass});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, AppRoutes.schedule),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(child: _ClassDetails(scheduledClass: scheduledClass)),
            _Thumbnail(asset: scheduledClass.imageAsset),
          ],
        ),
      ),
    );
  }
}

class _ClassDetails extends StatelessWidget {
  final ScheduledClass scheduledClass;
  const _ClassDetails({required this.scheduledClass});

  @override
  Widget build(BuildContext context) {
    final inSession = scheduledClass.inSession;
    final nameLabel = inSession
        ? '${scheduledClass.name} (In Session)'
        : scheduledClass.name;
    final nameColor = inSession
        ? DesignConstants.lightPrimary
        : DesignConstants.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(
          nameLabel,
          style: DesignConstants.h3.copyWith(color: nameColor),
        ),
        Text(
          '${scheduledClass.startTime} - ${scheduledClass.endTime}'
          ' (${scheduledClass.durationLabel})',
          style: DesignConstants.p.copyWith(color: DesignConstants.text),
        ),
        Text(
          scheduledClass.instructorName,
          style: DesignConstants.p.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
        if (scheduledClass.checkedInCount != null ||
            scheduledClass.attendingCount != null)
          _BookedCount(scheduledClass: scheduledClass),
      ],
    );
  }
}

class _BookedCount extends StatelessWidget {
  final ScheduledClass scheduledClass;
  const _BookedCount({required this.scheduledClass});

  @override
  Widget build(BuildContext context) {
    final isLive = scheduledClass.checkedInCount != null;
    final color = isLive
        ? DesignConstants.lightPrimary
        : DesignConstants.text2nd;
    final text = isLive
        ? '${scheduledClass.checkedInCount} checked in'
        : '${scheduledClass.attendingCount} attending';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.person_sharp,
          size: 16,
          color: color,
          weight: DesignConstants.iconWeight,
        ),
        Text(text, style: DesignConstants.p.copyWith(color: color)),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String? asset;
  const _Thumbnail({required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset == null) {
      return const SizedBox(width: 122, height: 73);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Image.asset(
        asset!,
        width: 122,
        height: 73,
        fit: BoxFit.cover,
      ),
    );
  }
}
