import 'package:crm/features/members/data/mock_videos.dart';

/// Compact view-count label: 168441 -> "168K", 1240000 -> "1.2M",
/// 942 -> "942". Returns "" when the count is hidden (null).
String formatViewCount(int? count) {
  if (count == null) return '';
  if (count < 1000) return '$count';
  if (count < 1000000) return '${(count / 1000).floor()}K';
  final millions = count / 1000000;
  final label = millions < 10
      ? millions.toStringAsFixed(1)
      : millions.floor().toString();
  return '${label}M';
}

/// "Coach Mike ‧ 168K views", dropping the views clause when hidden.
String videoMetaLabel(ManagedVideo video) {
  final views = formatViewCount(video.viewCount);
  return views.isEmpty
      ? video.channelName
      : '${video.channelName} ‧ $views views';
}

/// Title-case a backend wire value: `behind_the_scenes` -> `Behind The
/// Scenes`. The app owns no tag vocabulary, so labels derive from the wire.
String displayLabel(String wire) => wire
    .split('_')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');
