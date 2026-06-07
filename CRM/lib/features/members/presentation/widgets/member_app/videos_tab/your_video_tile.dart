import 'package:flutter/material.dart';

import 'package:crm/features/members/data/gym_detail.dart';
import 'package:crm/features/members/data/mock_videos.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_format_helpers.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';

/// The gym's own "Your videos" tiles, derived from the selected gym's classes
/// so the thumbnails, instructor avatars, and titles stay brand-consistent and
/// match the live feed's look (the rest of the videos tab is gym-driven too).
/// The first class becomes a rebranded "Welcome to {gym}" intro tile.
///
/// When the gym detail / classes aren't available (still loading, the service
/// is down, or a gym with no classes), it degrades to the bundled mock tiles
/// in [kMockVideos] so the demo never shows a blank "Your videos".
List<VideoTile> buildYourVideoTiles(GymDetail? detail, {required String gymName}) {
  final classes = detail?.classes ?? const <GymClass>[];
  if (classes.isEmpty) return _bundledFallbackTiles();

  final name = gymName.isEmpty ? 'your gym' : gymName;
  return [
    for (var i = 0; i < classes.length; i++)
      classVideoTile(
        classes[i],
        index: i,
        // The first class doubles as the gym's intro video.
        pillLabel: i == 0 ? 'Intro video' : null,
        titleOverride: i == 0 ? 'Welcome to $name' : null,
        channelOverride: i == 0 ? name : null,
      ),
  ];
}

/// Builds a [VideoTile] for one of the gym's classes. The class image and
/// instructor photo are live network urls; both fall back to a bundled asset
/// (cycled by [index]) when the gym serves an empty url, so a tile never goes
/// blank. The gym's videos are editable, so [VideoTile.showEdit] is on.
VideoTile classVideoTile(
  GymClass gymClass, {
  required int index,
  String? pillLabel,
  String? titleOverride,
  String? channelOverride,
}) {
  final channel = channelOverride ?? gymClass.instructorName;
  return VideoTile(
    thumbnail: gymClass.imageUrl.isNotEmpty
        ? NetworkImage(gymClass.imageUrl)
        : _fallbackThumb(index),
    avatar: gymClass.instructorImageUrl.isNotEmpty
        ? NetworkImage(gymClass.instructorImageUrl)
        : _fallbackAvatar(index),
    title: titleOverride ?? gymClass.name,
    meta: channel,
    pillLabel: pillLabel,
    showEdit: true,
  );
}

/// Builds a [VideoTile] for one of the gym's own uploads (mock data). Backs the
/// bundled fallback when live class data isn't available. The intro video
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

/// The bundled mock tiles, intro first (flagged with its pill) — the fallback
/// when the selected gym has no live classes to render.
List<VideoTile> _bundledFallbackTiles() {
  final intro = kMockVideos.introVideo;
  return [
    if (intro != null) yourVideoTile(intro, pillLabel: 'Intro video'),
    for (final video in kMockVideos.customVideos) yourVideoTile(video),
  ];
}

/// Bundled assets cycled as per-field fallbacks for classes with empty urls —
/// reusing the mock's own art so no new asset paths are introduced here.
ImageProvider _fallbackThumb(int index) {
  final pool = _fallbackThumbs;
  return AssetImage(pool[index % pool.length]);
}

ImageProvider _fallbackAvatar(int index) {
  final pool = _fallbackAvatars;
  return AssetImage(pool[index % pool.length]);
}

final List<String> _fallbackThumbs = [
  if (kMockVideos.introVideo != null) kMockVideos.introVideo!.thumbnailAsset,
  for (final v in kMockVideos.customVideos) v.thumbnailAsset,
];

final List<String> _fallbackAvatars = [
  if (kMockVideos.introVideo != null) kMockVideos.introVideo!.channelAvatarAsset,
  for (final v in kMockVideos.customVideos) v.channelAvatarAsset,
];
