import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/class_booking/data/mock_class_detail.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// How a layout arranges the instructor block.
///
/// The bio and the headshot are in every value; only where the
/// headshot sits and how big it is changes.
enum ClassInstructorLayout {
  /// Bio left, headshot trailing at full size. Ships today.
  avatarTrailing,

  /// Headshot centred above the bio — for a narrow pane.
  avatarTop,

  /// A compact strip: small headshot leading, bio filling the rest.
  row,
}

const double _kAvatarLg = 132;
const double _kAvatarSm = 56;

/// "Instructor" header + bio paragraph with a circular headshot.
/// Mirrors the `InstructorWidget` group.
class ClassInstructorSection extends StatelessWidget {
  const ClassInstructorSection({
    super.key,
    required this.detail,
    this.layout = ClassInstructorLayout.avatarTrailing,
  });

  final MockClassDetail detail;
  final ClassInstructorLayout layout;

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Instructor',
      spacing: DesignConstants.spacingMedium,
      child: switch (layout) {
        ClassInstructorLayout.avatarTrailing => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            Expanded(child: _Bio(detail: detail)),
            _Avatar(detail: detail, size: _kAvatarLg),
          ],
        ),
        ClassInstructorLayout.avatarTop => Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            _Avatar(detail: detail, size: _kAvatarLg),
            _Bio(detail: detail),
          ],
        ),
        ClassInstructorLayout.row => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: DesignConstants.spacingMedium,
          children: [
            _Avatar(detail: detail, size: _kAvatarSm),
            Expanded(child: _Bio(detail: detail)),
          ],
        ),
      },
    );
  }
}

class _Bio extends StatelessWidget {
  const _Bio({required this.detail});

  final MockClassDetail detail;

  @override
  Widget build(BuildContext context) {
    return Text(
      detail.classData.instructorBio,
      style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.detail, required this.size});

  final MockClassDetail detail;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image(
        image: CachedNetworkImageProvider(detail.classData.instructorImageUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => SizedBox(
          width: size,
          height: size,
          child: ColoredBox(color: DesignConstants.card),
        ),
      ),
    );
  }
}
