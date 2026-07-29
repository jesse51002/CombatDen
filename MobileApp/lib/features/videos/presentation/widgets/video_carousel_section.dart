import 'package:flutter/material.dart';
import 'package:mobile_app/features/videos/data/video.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_column.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_grid.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_row.dart';
import 'package:mobile_app/features/videos/presentation/widgets/sections/video_section_tall.dart';

/// How one tag's videos are arranged. A presentation prop: every value
/// renders the same title, the same "view all" action, and a card for
/// every video in the section.
enum VideoSectionLayout {
  /// Title over a horizontally-scrolling row of 258-wide cards.
  row,

  /// Title over a vertical column of width-filling cards, action last.
  stack,

  /// Band-divider title over a two-column tile grid, action as a tile.
  grid,

  /// A column of portrait cards, title overlaid on the first.
  tall,
}

/// A titled section holding one tag's videos plus its "view all"
/// affordance.
///
/// The layout that places a section decides its horizontal inset —
/// screen gutter, a narrower column beside a rail, or full bleed. The
/// one exception is [VideoSectionLayout.row], which insets its own
/// header and pads its own scroll view, because its cards have to run
/// past the gutter and off the edge.
class VideoCarouselSection extends StatelessWidget {
  const VideoCarouselSection({
    super.key,
    required this.title,
    required this.videos,
    this.layout = VideoSectionLayout.row,
    this.onViewAllTap,
    this.onVideoTap,
  });

  final String title;
  final List<Video> videos;
  final VideoSectionLayout layout;
  final VoidCallback? onViewAllTap;
  final ValueChanged<Video>? onVideoTap;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      VideoSectionLayout.row => VideoSectionRow(
        title: title,
        videos: videos,
        onViewAllTap: onViewAllTap,
        onVideoTap: onVideoTap,
      ),
      VideoSectionLayout.stack => VideoSectionColumn(
        title: title,
        videos: videos,
        onViewAllTap: onViewAllTap,
        onVideoTap: onVideoTap,
      ),
      VideoSectionLayout.grid => VideoSectionGrid(
        title: title,
        videos: videos,
        onViewAllTap: onViewAllTap,
        onVideoTap: onVideoTap,
      ),
      VideoSectionLayout.tall => VideoSectionTall(
        title: title,
        videos: videos,
        onViewAllTap: onViewAllTap,
        onVideoTap: onVideoTap,
      ),
    };
  }
}
