import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:crm/features/members/data/video_feed.dart';
import 'package:crm/features/members/presentation/widgets/member_app/videos_tab/video_tile.dart';

/// Opens [url] (a YouTube watch page) in a new browser tab on web; falls back to
/// the platform handler elsewhere. No-op for an empty / unparseable url.
Future<void> openVideoInNewTab(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, webOnlyWindowName: '_blank');
}

/// Builds an editable, clickable [VideoTile] for one video in the gym's own
/// feed: tapping the thumbnail opens the watch page in a new tab, and Remove
/// deletes it from the feed via [onRemove]. An owner-added URL-only video has no
/// title/channel yet, so those fall back to friendly placeholders.
VideoTile feedVideoTile(Video video, {required VoidCallback onRemove}) {
  return VideoTile(
    // Use the stored thumbnail; show nothing when there isn't one.
    thumbnail: video.thumbnailUrl.isNotEmpty
        ? NetworkImage(video.thumbnailUrl)
        : null,
    avatar: NetworkImage(video.channelAvatarUrl),
    title: video.title.isNotEmpty ? video.title : 'Custom video',
    meta: video.metaLabel.isNotEmpty ? video.metaLabel : 'YouTube',
    onTap: () => openVideoInNewTab(video.url),
    onRemove: onRemove,
  );
}
