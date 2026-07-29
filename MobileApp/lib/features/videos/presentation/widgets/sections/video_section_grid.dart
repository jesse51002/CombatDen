import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_header.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_carousel_card.dart';
import 'package:mobile_app/features/videos/presentation/widgets/video_view_all_action.dart';

/// A tag section as a two-column tile grid under an inline band
/// divider, with the "view all" action taking the last cell.
///
/// Laid out as rows of [_kColumns] rather than a `GridView` so the
/// section keeps its natural height inside the page's own scroll.
class VideoSectionGrid extends StatelessWidget {
  const VideoSectionGrid({
    super.key,
    required this.title,
    required this.videos,
    this.onViewAllTap,
    this.onVideoTap,
  });

  final String title;
  final List<Video> videos;
  final VoidCallback? onViewAllTap;
  final ValueChanged<Video>? onVideoTap;

  static const int _kColumns = 2;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (final v in videos)
        VideoCarouselCard(
          video: v,
          size: VideoCardSize.tile,
          onTap: () => onVideoTap?.call(v),
        ),
      VideoViewAllAction(
        onTap: onViewAllTap,
        style: VideoViewAllStyle.tile,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        VideoSectionHeader(
          title: title,
          style: VideoSectionHeaderStyle.divider,
          showViewAll: false,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: DesignConstants.spacingLarge,
          children: [
            for (var i = 0; i < cells.length; i += _kColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignConstants.spacingLarge,
                children: [
                  for (var column = 0; column < _kColumns; column++)
                    if (i + column < cells.length)
                      Expanded(child: cells[i + column])
                    else
                      const Spacer(),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
