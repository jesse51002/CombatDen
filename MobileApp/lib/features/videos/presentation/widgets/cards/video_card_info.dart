import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/data/video_helpers.dart';

/// Channel avatar + title + view count — the meta line every video card
/// carries, whatever shape the card takes.
class VideoCardInfo extends StatelessWidget {
  const VideoCardInfo({
    super.key,
    required this.video,
    this.compact = false,
  });

  final Video video;

  /// Shrinks the avatar for the denser card shapes (grid tiles, the
  /// caption band on a tall card). Text styles are unchanged.
  final bool compact;

  static const double _kPfpSize = 35;
  static const double _kPfpSizeCompact = 28;

  @override
  Widget build(BuildContext context) {
    final pfp = compact ? _kPfpSizeCompact : _kPfpSize;
    final views = formatViewCount(video.viewCount);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipOval(
          child: Image(
            image: CachedNetworkImageProvider(video.channelAvatarUrl),
            width: pfp,
            height: pfp,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: pfp,
              height: pfp,
              child: ColoredBox(color: DesignConstants.card),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  video.title,
                  style: DesignConstants.p,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  views.isEmpty ? video.channelName : '$views views',
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
