import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_videos.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';
import 'package:app_management/shared/widgets/app_outline_button.dart';
import 'package:app_management/shared/widgets/horizontal_scroller.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Your videos" section: the gym's own uploads. The intro video leads
/// the list, flagged with an "Intro video" pill. Plus a way to add more.
class CustomVideosSection extends StatelessWidget {
  const CustomVideosSection({super.key});

  @override
  Widget build(BuildContext context) {
    final intro = kMockVideos.introVideo;
    final custom = kMockVideos.customVideos;
    return SubtitleSection(
      title: 'Your videos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          HorizontalScroller(
            children: [
              if (intro != null) _tile(intro, pillLabel: 'Intro video'),
              for (final video in custom) _tile(video),
            ],
          ),
          AppOutlineButton(
            text: 'Add custom video',
            icon: Icon(
              Symbols.add_sharp,
              color: DesignConstants.text,
              weight: DesignConstants.iconWeight,
              size: 20,
            ),
            onPressed: () => debugPrint('TODO: add custom video'),
          ),
        ],
      ),
    );
  }

  VideoTile _tile(ManagedVideo video, {String? pillLabel}) {
    return VideoTile(
      thumbnail: AssetImage(video.thumbnailAsset),
      avatar: AssetImage(video.channelAvatarAsset),
      title: video.title,
      meta: videoMetaLabel(video),
      pillLabel: pillLabel,
      showEdit: true,
    );
  }
}
