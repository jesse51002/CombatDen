import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';

/// The thumbnail block of a video card.
///
/// Two shapes, because a card is sized either by a fixed thumbnail
/// height (the 258-wide carousel card) or by an aspect ratio (every
/// width-filling card). Both are per-asset image dimensions, not
/// design tokens.
class VideoCardThumb extends StatelessWidget {
  /// A thumbnail of exactly [height] logical pixels.
  const VideoCardThumb.fixed({
    super.key,
    required this.video,
    required double this.height,
  }) : aspectRatio = null;

  /// A thumbnail that fills its width at [aspectRatio] (w / h).
  const VideoCardThumb.ratio({
    super.key,
    required this.video,
    required double this.aspectRatio,
  }) : height = null;

  final Video video;
  final double? height;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: CachedNetworkImageProvider(video.thumbnailUrl),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(color: DesignConstants.card),
    );
    if (height != null) return SizedBox(height: height, child: image);
    return AspectRatio(aspectRatio: aspectRatio!, child: image);
  }
}
