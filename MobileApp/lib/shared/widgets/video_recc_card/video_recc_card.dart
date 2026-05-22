import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Full-width video recommendation card.
///
/// Used on `VideosScreen` (via featured / "Technique of the Day" wrappers)
/// and on the recommendation surfaces. Layout: 16:9 thumbnail with rounded
/// corners, then a row with the creator's avatar, the video title, and a
/// meta line. Images are [ImageProvider]s so the caller chooses the source
/// (live network thumbnails go through `cached_network_image`).
class VideoReccCard extends StatelessWidget {
  const VideoReccCard({
    super.key,
    required this.title,
    required this.metaLabel,
    required this.thumbnail,
    required this.creatorPfp,
    this.roundThumbnail = true,
    this.onTap,
  });

  final String title;
  final String metaLabel;
  final ImageProvider thumbnail;
  final ImageProvider creatorPfp;

  /// Rounds the thumbnail's corners. Standalone cards want this; the
  /// featured card sets it false because its outer surface already rounds
  /// the top and a rounded thumbnail bottom reads as a notch mid-card.
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
  final ImageProvider creatorPfp;

  static const double _kPfpSize = 55;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: DesignConstants.paddingSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: DesignConstants.spacingMedium,
        children: [
          ClipOval(
            child: Image(
              image: creatorPfp,
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
