import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';

/// Class title + location/time/attending block. Mirrors the Figma
/// `ClassMetatext` group.
class ClassMetaSection extends StatelessWidget {
  const ClassMetaSection({super.key, required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(detail.classData.name, style: DesignConstants.h1),
        _SpecificsBlock(detail: detail),
      ],
    );
  }
}

class _SpecificsBlock extends StatelessWidget {
  const _SpecificsBlock({required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    final cls = detail.classData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingTiny,
      children: [
        _MetaText(detail.location),
        _MetaText('${detail.dateLabel} ‧ ${cls.timeRange}'),
        if (cls.attending != null) _AttendingRow(count: cls.attending!),
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
          color: DesignConstants.of(context).primaryColor,
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
