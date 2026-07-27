import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';
import 'package:mobile_app/shared/widgets/class_reserved_tag.dart';

/// Class title + reserved status + gym / date / instructor / attending block,
/// from the real occurrence.
///
/// The order is deliberate: what this class IS, then where the member STANDS
/// with it, then the facts. The reservation is the member's own relationship
/// to the class, so it is answered before the details rather than being left
/// to be inferred from a "Cancel reservation" button at the far end of the
/// screen.
class ClassMetaSection extends StatelessWidget {
  const ClassMetaSection({
    super.key,
    required this.occurrence,
    required this.gymName,
    this.reserved = false,
  });

  final ClassOccurrence occurrence;
  final String gymName;

  /// The member holds this occurrence.
  final bool reserved;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(occurrence.className, style: DesignConstants.h1),
        if (reserved) const ClassReservedTag(),
        _SpecificsBlock(occurrence: occurrence, gymName: gymName),
      ],
    );
  }
}

class _SpecificsBlock extends StatelessWidget {
  const _SpecificsBlock({required this.occurrence, required this.gymName});

  final ClassOccurrence occurrence;
  final String gymName;

  @override
  Widget build(BuildContext context) {
    final date = parseIsoDate(occurrence.classDate);
    final dayLabel = date != null
        ? fullDayLabelForOffset(dayOffsetForDate(date))
        : occurrence.classDate;
    final range = formatSlotRange(
      occurrence.resolvedClassTime,
      occurrence.resolvedDurationMinutes,
    );
    final instructor = occurrence.resolvedInstructorName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingTiny,
      children: [
        if (gymName.isNotEmpty) _MetaText(gymName),
        _MetaText('$dayLabel ‧ $range'),
        if (instructor != null && instructor.isNotEmpty)
          _MetaText('with $instructor'),
        _AttendingRow(count: occurrence.signupCount),
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
    );
  }
}

class _AttendingRow extends StatelessWidget {
  const _AttendingRow({required this.count});

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
          color: DesignConstants.primaryColor,
          size: DesignConstants.iconSizeSm,
        ),
        Text(
          '$count attending',
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
        ),
      ],
    );
  }
}
