import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_readout_card.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/chart_scale.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/series/drawn_series.dart';

/// The hover read-out for one bucket of a time-series chart: the bucket's
/// own date, then every series' exact value in it.
///
/// Built lazily on hover — never in the paint path.
ChartReadout seriesReadout({
  required SeriesBundle bundle,
  required int index,
  required MetricUnit unit,
  required String granularity,
}) {
  return ChartReadout(
    title: bucketLabelLong(bundle.dates[index], granularity),
    lines: [
      for (final s in bundle.series)
        ChartReadoutLine(
          swatch: s.color,
          label: s.label,
          value: index < s.values.length && s.values[index] != null
              ? formatMetricValue(s.values[index]!, unit)
              : '—',
        ),
    ],
  );
}

/// The one-sentence summary a screen reader gets in place of the painted
/// marks: the newest bucket and what each series read there.
String seriesSummary(
  SeriesBundle bundle,
  MetricUnit unit,
  String granularity,
) {
  if (bundle.isEmpty) return 'No data';
  final label = bucketLabelLong(bundle.dates.last, granularity);
  final parts = [
    for (final s in bundle.series)
      '${s.label} ${formatMetricValue(s.lastValue ?? 0, unit)}',
  ];
  return '$label: ${parts.join(', ')}';
}
