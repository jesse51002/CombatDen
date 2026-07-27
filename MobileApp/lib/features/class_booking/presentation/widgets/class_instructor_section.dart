import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Instructor" header + bio paragraph next to a circular headshot.
/// Mirrors the `InstructorWidget` group.
class ClassInstructorSection extends StatelessWidget {
  const ClassInstructorSection({super.key, required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Instructor',
      spacing: DesignConstants.spacingMedium,
      child: _InstructorRow(detail: detail),
    );
  }
}

class _InstructorRow extends StatelessWidget {
  const _InstructorRow({required this.detail});

  final MockClassDetail detail;

  static const double _kPfpSize = 132;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: Text(
            detail.classData.instructorBio,
            style: DesignConstants.pBig.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        ClipOval(
          child: Image(
            image: CachedNetworkImageProvider(
              detail.classData.instructorImageUrl,
            ),
            width: _kPfpSize,
            height: _kPfpSize,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: _kPfpSize,
              height: _kPfpSize,
              child: ColoredBox(color: DesignConstants.card),
            ),
          ),
        ),
      ],
    );
  }
}
