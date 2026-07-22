import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// The Growth page's time window, applied **client-side**.
///
/// The wire carries a metric's full history, so narrowing the window is a
/// pure reshape of the data already in memory — no refetch, no loading
/// state. Only `line` and `bars` carry time series; every other payload is
/// a current-state snapshot and is left untouched.
enum GrowthRange {
  all('All', null),
  year('Year', 12),
  sixMonths('6M', 6),
  threeMonths('3M', 3);

  const GrowthRange(this.label, this.months);

  /// The pill's label.
  final String label;

  /// How far back the window reaches from a series' newest point; null for
  /// [all], which keeps every point.
  final int? months;

  /// The subtitle a trimmed section carries, so a narrowed window is never
  /// invisible. Null for [all] — the section keeps its own window label.
  String? get windowLabel => switch (this) {
        GrowthRange.all => null,
        GrowthRange.year => 'Last 12 months',
        GrowthRange.sixMonths => 'Last 6 months',
        GrowthRange.threeMonths => 'Last 3 months',
      };
}

/// Whether [metric] carries time series the range pill can trim.
bool metricHasSeries(GrowthMetric metric) =>
    metric.data is LineData || metric.data is BarsData;

/// Whether any metric in [metrics] carries a trimmable time series — the
/// condition for showing the range pill at all.
bool anyMetricHasSeries(Iterable<GrowthMetric> metrics) =>
    metrics.any(metricHasSeries);

/// [metric] with every series trimmed to [range], or [metric] itself when
/// the range is [GrowthRange.all] or the payload carries no series.
///
/// The renderers take PRE-TRIMMED data — that is their contract — so the
/// trim happens here, on the envelope, before the payload is handed over.
GrowthMetric trimMetricToRange(GrowthMetric metric, GrowthRange range) {
  final months = range.months;
  if (months == null) return metric;

  final GrowthMetricData trimmed;
  switch (metric.data) {
    case final LineData data:
      trimmed = LineData(
        unit: data.unit,
        granularity: data.granularity,
        series: _trimSeries(data.series, months),
        byClass: _trimByClass(data.byClass, months),
      );
    case final BarsData data:
      trimmed = BarsData(
        unit: data.unit,
        granularity: data.granularity,
        series: _trimSeries(data.series, months),
        byClass: _trimByClass(data.byClass, months),
      );
    default:
      return metric;
  }

  return GrowthMetric(
    key: metric.key,
    name: metric.name,
    categories: metric.categories,
    type: metric.type,
    order: metric.order,
    computedAt: metric.computedAt,
    data: trimmed,
  );
}

List<ClassSeries>? _trimByClass(List<ClassSeries>? byClass, int months) {
  if (byClass == null) return null;
  return [
    for (final c in byClass)
      ClassSeries(
        classId: c.classId,
        className: c.className,
        series: _trimSeries(c.series, months),
      ),
  ];
}

List<MetricSeries> _trimSeries(List<MetricSeries> series, int months) =>
    [for (final s in series) _trimOne(s, months)];

/// Keeps the points within [months] of THIS series' newest point.
///
/// The window is anchored per series rather than per page: a series that
/// stops early still shows its own last N months instead of collapsing to
/// nothing because a neighbouring series runs later.
MetricSeries _trimOne(MetricSeries series, int months) {
  DateTime? newest;
  for (final p in series.points) {
    final d = DateTime.tryParse(p.date);
    if (d != null && (newest == null || d.isAfter(newest))) newest = d;
  }
  if (newest == null) return series;

  final cutoff = DateTime(newest.year, newest.month - months, newest.day);
  final kept = [
    // A point whose date will not parse is KEPT: dropping data we cannot
    // judge would silently lose it.
    for (final p in series.points)
      if (!(DateTime.tryParse(p.date)?.isBefore(cutoff) ?? false)) p,
  ];
  if (kept.length == series.points.length) return series;
  return MetricSeries(key: series.key, label: series.label, points: kept);
}
