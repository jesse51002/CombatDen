import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_attending_row.dart';
import 'package:mobile_app/features/class_booking/presentation/widgets/class_meta_spec_table.dart';

/// How a layout arranges the class meta block.
///
/// Every value renders the same facts: title, location, date, time and
/// the attending count. Only their shape and their surface change.
enum ClassMetaLayout {
  /// Title over the specifics, on the page background. Ships today.
  stacked,

  /// The same block, sitting on the photo behind a scrim.
  overlay,

  /// Title beside an inline photo thumb, specifics as a label/value
  /// table.
  specTable,
}

/// Class title + location/time/attending block. Mirrors the
/// `ClassMetatext` group.
class ClassMetaSection extends StatelessWidget {
  const ClassMetaSection({
    super.key,
    required this.detail,
    this.layout = ClassMetaLayout.stacked,
    this.leading,
  });

  final MockClassDetail detail;
  final ClassMetaLayout layout;

  /// Presentation slot used by [ClassMetaLayout.specTable] only: the
  /// class photo, inline with the title instead of above the block.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      ClassMetaLayout.stacked => _StackedMeta(detail: detail),
      ClassMetaLayout.overlay => _OverlayMeta(detail: detail),
      ClassMetaLayout.specTable => ClassMetaSpecTable(
        detail: detail,
        leading: leading,
      ),
    };
  }
}

class _StackedMeta extends StatelessWidget {
  const _StackedMeta({required this.detail});

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

/// The stacked block on a fade to the page background, so it reads
/// against a photograph instead of against the page.
class _OverlayMeta extends StatelessWidget {
  const _OverlayMeta({required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            DesignConstants.backgroundColor.withValues(alpha: 0),
            DesignConstants.backgroundColor.withValues(alpha: 0.94),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          DesignConstants.screenHorizontalPadding,
          DesignConstants.spacingBig,
          DesignConstants.screenHorizontalPadding,
          DesignConstants.spacingLarge,
        ),
        child: _StackedMeta(detail: detail),
      ),
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
        if (cls.attending != null) ClassAttendingRow(count: cls.attending!),
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
