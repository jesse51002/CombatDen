import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/subtitle_section.dart';

/// "Instructor" header + bio paragraph next to a circular headshot.
///
/// Fed by the resolved instructor's real fields on the board occurrence
/// (`resolved_instructor_name` / `_bio` / `_image_url`). Renders nothing when
/// the occurrence has no instructor and no bio to show.
class ClassInstructorSection extends StatelessWidget {
  const ClassInstructorSection({
    super.key,
    required this.name,
    required this.bio,
    required this.imageUrl,
  });

  final String? name;
  final String? bio;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final bioText = bio?.trim();
    final hasBio = bioText != null && bioText.isNotEmpty;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    // Nothing to show without at least a bio or a photo — the bare name
    // already appears in the meta section.
    if (!hasBio && !hasImage) return const SizedBox.shrink();
    return SubtitleSection(
      title: 'Instructor',
      spacing: DesignConstants.spacingMedium,
      child: _InstructorRow(
        bio: hasBio ? bioText : null,
        imageUrl: hasImage ? imageUrl : null,
      ),
    );
  }
}

class _InstructorRow extends StatelessWidget {
  const _InstructorRow({required this.bio, required this.imageUrl});

  final String? bio;
  final String? imageUrl;

  static const double _kPfpSize = 132;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        if (bio != null)
          Expanded(
            child: Text(
              bio!,
              style: DesignConstants.pBig.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ),
        if (imageUrl != null)
          ClipOval(
            child: Image(
              image: CachedNetworkImageProvider(imageUrl!),
              width: _kPfpSize,
              height: _kPfpSize,
              fit: BoxFit.cover,
              // A headshot that fails to load collapses to nothing, exactly
              // like an absent one — the same rule the creator avatar uses.
              // A filled disc where a face should be reads as a broken
              // profile, which is worse than the bio simply taking the width.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
