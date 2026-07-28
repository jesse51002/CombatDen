import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/presentation/widgets/cards/video_card_info.dart';
import 'package:mobile_app/features/videos/presentation/widgets/cards/video_card_thumb.dart';

/// How a [VideoCarouselCard] is shaped. A presentation prop only: every
/// size renders the same thumbnail, title, channel avatar and view
/// count, and taps the same callback.
enum VideoCardSize {
  /// 258 wide with a fixed 145 thumbnail — the card the horizontal tag
  /// rows ship today.
  md,

  /// Fills its column at 16:9.
  lg,

  /// Fills its grid cell at 16:9 with a denser meta line.
  tile,

  /// Portrait 3:4 with the meta line as a caption band over the image.
  tall,
}

/// Compact video card used by every tag section.
class VideoCarouselCard extends StatelessWidget {
  const VideoCarouselCard({
    super.key,
    required this.video,
    this.size = VideoCardSize.md,
    this.onTap,
  });

  final Video video;
  final VideoCardSize size;
  final VoidCallback? onTap;

  static const double _kCardWidth = 258;
  static const double _kThumbHeight = 145;
  static const double _kTallAspect = 3 / 4;
  static const double _kWideAspect = 16 / 9;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: switch (size) {
        VideoCardSize.md => SizedBox(
          width: _kCardWidth,
          child: _Framed(
            thumb: VideoCardThumb.fixed(
              video: video,
              height: _kThumbHeight,
            ),
            info: VideoCardInfo(video: video),
          ),
        ),
        VideoCardSize.lg => _Framed(
          thumb: VideoCardThumb.ratio(video: video, aspectRatio: _kWideAspect),
          info: VideoCardInfo(video: video),
        ),
        VideoCardSize.tile => _Framed(
          thumb: VideoCardThumb.ratio(video: video, aspectRatio: _kWideAspect),
          info: VideoCardInfo(video: video, compact: true),
        ),
        VideoCardSize.tall => _Captioned(video: video),
      },
    );
  }
}

/// Thumbnail over meta line on the card surface — the shipped shape.
class _Framed extends StatelessWidget {
  const _Framed({required this.thumb, required this.info});

  final Widget thumb;
  final Widget info;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingLarge,
        children: [
          thumb,
          Padding(
            padding: EdgeInsets.fromLTRB(
              DesignConstants.spacingMedium,
              0,
              DesignConstants.spacingMedium,
              DesignConstants.spacingLarge,
            ),
            child: info,
          ),
        ],
      ),
    );
  }
}

/// Portrait thumbnail with the meta line riding a caption band over its
/// bottom edge.
class _Captioned extends StatelessWidget {
  const _Captioned({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    // The card surface sits behind the artwork, not just around it: a
    // thumbnail that is still loading (or gone) has to leave a card,
    // not a hole in the column.
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          VideoCardThumb.ratio(
            video: video,
            aspectRatio: VideoCarouselCard._kTallAspect,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: DesignConstants.popup,
              child: Padding(
                padding: EdgeInsets.all(DesignConstants.spacingMedium),
                child: VideoCardInfo(video: video, compact: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
