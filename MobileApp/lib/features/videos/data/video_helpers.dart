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

/// Human-readable label for a backend wire value: `behind_the_scenes` →
/// `Behind The Scenes`. Renders any string the server sends — the app owns no
/// tag/group vocabulary, so titles and tab labels derive straight from the
/// wire string.
String displayLabel(String wire) => wire
    .split('_')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');
