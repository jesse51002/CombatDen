import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';

// Thumbnail size mirrors the home board's class row (per-asset layout values).
const double _kThumbWidth = 122;
const double _kThumbHeight = 73;

/// One pickable class on the check-in pick-class step. Composes the same
/// fields the home board's `ClassListItem` shows (name, time, instructor,
/// image) but stands alone — it carries no HomeBloc coupling and no
/// booked/attending state, since here the member is choosing what to check
/// into. Tapping fires [onTap] with this occurrence.
class PickClassCard extends StatelessWidget {
  const PickClassCard({
    super.key,
    required this.occurrence,
    required this.onTap,
  });

  final ClassOccurrence occurrence;
  final ValueChanged<ClassOccurrence> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(occurrence),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.screenHorizontalPadding,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingLarge,
          children: [
            Expanded(child: _ClassInfo(occurrence: occurrence)),
            _Thumbnail(imageUrl: occurrence.imageUrl),
          ],
        ),
      ),
    );
  }
}

class _ClassInfo extends StatelessWidget {
  const _ClassInfo({required this.occurrence});

  final ClassOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final range = formatSlotRange(
      occurrence.resolvedClassTime,
      occurrence.resolvedDurationMinutes,
    );
    final mentor = occurrence.resolvedInstructorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingSmall,
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
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Image(
        image: CachedNetworkImageProvider(imageUrl),
        width: _kThumbWidth,
        height: _kThumbHeight,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => SizedBox(
          width: _kThumbWidth,
          height: _kThumbHeight,
          child: ColoredBox(color: DesignConstants.card),
        ),
      ),
    );
  }
}
