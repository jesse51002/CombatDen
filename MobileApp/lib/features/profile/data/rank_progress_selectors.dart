import 'package:mobile_app/features/profile/data/models/rank_progress_point.dart';

/// The rank-graph timeframe window: a client-side filter over the returned
/// points (there is no server-side windowing). [all] keeps the whole series.
enum RankTimeframe {
  week('1W', 7),
  month('1M', 30),
  year('1Y', 365),
  all('ALL', null);

  const RankTimeframe(this.label, this.days);

  /// The pill label.
  final String label;

  /// The trailing window length in days, or null for [all] (no window).
  final int? days;
}

/// Map the rank-progress points to the normalized 0..1 sawtooth the graph
/// plots: each point's classes-into-rank as a fraction of its per-step
/// threshold, clamped to 0..1. The reset-to-0 at each promotion is already
/// encoded in the data (the backend resets `classesIntoRank` at a
/// `rank_changed`); the clamp is a defensive cap at the threshold, and a
/// non-positive threshold maps to 0 (never divides by zero).
List<double> plottableSeries(List<RankProgressPoint> points) {
  return [
    for (final p in points)
      if (p.classesNeeded <= 0)
        0.0
      else
        (p.classesIntoRank / p.classesNeeded).clamp(0.0, 1.0),
  ];
}

/// Filter the points to [tf]'s trailing window, anchored at the latest point's
/// day (so a member who last trained weeks ago still sees their real recent
/// history, not an empty 1W). [RankTimeframe.all] returns the points unchanged.
/// Points whose date can't be parsed are kept (never hide real data).
List<RankProgressPoint> windowPoints(
  List<RankProgressPoint> points,
  RankTimeframe tf,
) {
  final days = tf.days;
  if (days == null || points.isEmpty) return points;

  DateTime? anchor;
  for (final p in points) {
    final parsed = DateTime.tryParse(p.date);
    if (parsed != null) anchor = parsed;
  }
  if (anchor == null) return points;

  final cutoff = anchor.subtract(Duration(days: days));
  final result = <RankProgressPoint>[];
  for (final p in points) {
    final parsed = DateTime.tryParse(p.date);
    // Keep unparseable dates (never hide real data); otherwise apply the window.
    if (parsed == null || !parsed.isBefore(cutoff)) result.add(p);
  }
  return result;
}
