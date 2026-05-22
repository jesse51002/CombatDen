import 'package:mobile_app/features/videos/data/video.dart';

/// Compact view-count label: 168441 → "168K", 1_240_000 → "1.2M",
/// 942 → "942". Returns "" when the count is hidden (null) so callers can
/// drop the "views" clause entirely.
String formatViewCount(int? count) {
  if (count == null) return '';
  if (count < 1000) return '$count';
  if (count < 1000000) {
    return '${(count / 1000).floor()}K';
  }
  final millions = count / 1000000;
  // One decimal under 10M ("1.2M"), whole millions above ("12M").
  final label = millions < 10
      ? millions.toStringAsFixed(1)
      : millions.floor().toString();
  return '${label}M';
}

/// Human-readable carousel/section title for a fine-grained tag. Backend
/// hands us lowercase wire values; capitalize for display.
String tagDisplayName(VideoTag tag) => switch (tag) {
  VideoTag.educational => 'Educational',
  VideoTag.tutorial => 'Tutorials',
  VideoTag.informative => 'Informative',
  VideoTag.news => 'News',
  VideoTag.review => 'Reviews',
  VideoTag.interview => 'Interviews',
  VideoTag.entertainment => 'Entertainment',
  VideoTag.vlog => 'Vlogs',
  VideoTag.behindTheScenes => 'Behind the Scenes',
  VideoTag.professional => 'Pro Footage',
  VideoTag.clips => 'Clips',
  VideoTag.fun => 'Fun',
  VideoTag.unknown => 'More',
};
