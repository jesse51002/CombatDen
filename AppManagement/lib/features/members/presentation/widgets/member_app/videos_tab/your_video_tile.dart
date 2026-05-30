import 'package:flutter/material.dart';

import 'package:app_management/features/members/data/mock_videos.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';
import 'package:app_management/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';

/// Builds a [VideoTile] for one of the gym's own uploads (mock data). The
/// gym's videos are editable, so [VideoTile.showEdit] is on; the intro video
/// passes a [pillLabel] of "Intro video".
VideoTile yourVideoTile(ManagedVideo video, {String? pillLabel}) {
  return VideoTile(
    thumbnail: AssetImage(video.thumbnailAsset),
    avatar: AssetImage(video.channelAvatarAsset),
    title: video.title,
    meta: videoMetaLabel(video),
    pillLabel: pillLabel,
    showEdit: true,
  );
}

/// The gym's own videos, intro first (flagged with its pill), in the order the
/// "Your videos" row and grid both render them.
List<VideoTile> buildYourVideoTiles() {
  final intro = kMockVideos.introVideo;
  return [
    if (intro != null) yourVideoTile(intro, pillLabel: 'Intro video'),
    for (final video in kMockVideos.customVideos) yourVideoTile(video),
  ];
}
