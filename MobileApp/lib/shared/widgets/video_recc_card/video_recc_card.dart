import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/video_recc_card/creator_avatar.dart';

/// Full-width video recommendation card.
///
/// Used on `VideosScreen` (via the featured hero wrapper) and on the
/// recommendation surfaces. Layout: a square-cornered 16:9 thumbnail, then a
/// row with the creator's avatar, the video title, and a meta line. Images are
/// [ImageProvider]s so the caller chooses the source (live network thumbnails
/// go through `cached_network_image`).
///
/// [creatorPfp] is nullable: pass null (via `creatorAvatarProvider`) when the
/// video carries no avatar and the row renders the text alone, with no
/// placeholder circle and no leftover gap.
class VideoReccCard extends StatelessWidget {
  const VideoReccCard({
    super.key,
    required this.title,
    required this.metaLabel,
    required this.thumbnail,
    required this.creatorPfp,
    this.roundThumbnail = false,
    this.onTap,
  });

  final String title;
  final String metaLabel;
  final ImageProvider thumbnail;

  /// The creator's avatar, or null when the video has none.
  final ImageProvider? creatorPfp;

  /// Opt-in corner rounding for the thumbnail. Off by default: a YouTube
  /// thumbnail carries burnt-in text right to its edges, and a `radiusBig`
  /// corner on a full-width image clips that text. (The featured card's outer
  /// surface rounds the top anyway, and a rounded thumbnail bottom would read
  /// as a notch mid-card.) Only turn it on where the design frames the
  /// thumbnail with enough inset that nothing is lost.
  final bool roundThumbnail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget thumb = AspectRatio(
      aspectRatio: 16 / 9,
      child: Image(
        image: thumbnail,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
      ),
    );
    if (roundThumbnail) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        child: thumb,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          thumb,
          _CreatorRow(
            title: title,
            metaLabel: metaLabel,
            creatorPfp: creatorPfp,
          ),
        ],
      ),
    );
  }
}

class _CreatorRow extends StatelessWidget {
  const _CreatorRow({
    required this.title,
    required this.metaLabel,
    required this.creatorPfp,
  });

  final String title;
  final String metaLabel;
  final ImageProvider? creatorPfp;

  static const double _kPfpSize = 55;

  @override
  Widget build(BuildContext context) {
    final pfp = creatorPfp;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        // With no avatar the Expanded text is the row's only child, so the
        // spacing contributes nothing and the text starts at the edge.
        spacing: DesignConstants.spacingMedium,
        children: [
          if (pfp != null) CreatorAvatar(image: pfp, size: _kPfpSize),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(title, style: DesignConstants.h2),
                Text(
                  metaLabel,
                  style: DesignConstants.p.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
