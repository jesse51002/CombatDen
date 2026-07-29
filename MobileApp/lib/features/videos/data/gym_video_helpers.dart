/// Compact view-count label: 168441 → "168K", 1_240_000 → "1.2M", 942 → "942".
/// Returns "" when the count is hidden (null) so callers can drop the "views"
/// clause entirely.
///
/// The videos-tab display helper over the portal `GymVideoCard` (the old
/// `video_helpers.dart` is the same shape over the retired `Video` model).
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
