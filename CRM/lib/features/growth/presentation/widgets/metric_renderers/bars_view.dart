import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/companion_table_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_frame.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_hover_layer.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_legend.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_note.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/series_readout.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/chart_scale.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/bars_painter.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/series/drawn_series.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// Metrics whose two series are a good/bad PAIR rather than two peers.
///
/// These render diverging (good up, bad down) because green and red collapse
/// under deuteranopia — position has to carry the identity, not hue.
const Set<String> kPolarBarsMetrics = {'members_gained_lost'};

/// Past this many buckets a bar chart stops being readable; the newest
/// window is kept and the chart says so.
const int kMaxBarBuckets = 40;

/// Renders a `bars` metric in one of three deterministic modes: grouped
/// (1-2 peer series), stacked (3 series), or diverging (a good/bad pair).
class BarsView extends StatelessWidget {
  final BarsData data;
  final String metricKey;
  final String name;

  /// The selected class chip, when the metric carries `by_class`.
  final String? classId;

  const BarsView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
    this.classId,
  });

  BarsMode _modeFor(int seriesCount) {
    if (seriesCount == 2 && kPolarBarsMetrics.contains(metricKey)) {
      return BarsMode.diverging;
    }
    if (seriesCount >= 3) return BarsMode.stacked;
    return BarsMode.grouped;
  }

  @override
  Widget build(BuildContext context) {
    final full = buildSeriesBundle(
      seriesForClass(data.series, data.byClass, classId),
    );
    if (full.isEmpty) {
      return EmptyState.inline(
        icon: Symbols.show_chart_sharp,
        title: 'No $name history yet',
        body: 'This fills in as the gym records data. Check back after '
            'your first full month.',
      );
    }

    final trimmed = full.dates.length > kMaxBarBuckets;
    final bundle = full.takeNewest(kMaxBarBuckets);
    final mode = _modeFor(bundle.series.length);
    final series = mode == BarsMode.diverging
        ? _divergingColors(bundle.series)
        : bundle.series;

    final niceMax = niceCeiling(
      mode == BarsMode.stacked ? bundle.maxStackedValue : bundle.maxValue,
    );
    final ticks = mode == BarsMode.diverging
        ? [niceMax, 0.0, -niceMax]
        : yTicksFor(niceMax);

    final notes = <String>[
      if (bundle.dates.length == 1) 'Only one period so far',
      if (trimmed) 'Showing the last $kMaxBarBuckets periods',
    ];

    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        if (series.length >= 2)
          ChartLegend(
            entries: [
              for (final s in series)
                ChartLegendEntry(
                  color: s.color,
                  label: '${s.label} '
                      '${formatMetricValue(s.total, data.unit)}',
                ),
            ],
          ),
        Semantics(
          label: name,
          value: seriesSummary(bundle, data.unit, data.granularity),
          child: ChartFrame(
            yTicks: ticks,
            unit: data.unit,
            dates: bundle.dates,
            granularity: data.granularity,
            xOf: (i, width) => barsXOf(i, bundle.dates.length, width),
            plot: ChartHoverLayer(
              bucketCount: bundle.dates.length,
              xOf: (i, width) => barsXOf(i, bundle.dates.length, width),
              readoutFor: (i) => seriesReadout(
                bundle: SeriesBundle(
                  dates: bundle.dates,
                  series: series,
                  folded: bundle.folded,
                ),
                index: i,
                unit: data.unit,
                granularity: data.granularity,
              ),
              child: CustomPaint(
                size: Size.infinite,
                painter: BarsPainter(
                  series: series,
                  mode: mode,
                  maxY: niceMax,
                  gridTicks: ticks,
                  newestTotalLabel: mode == BarsMode.stacked
                      ? formatMetricValue(
                          _newestTotal(bundle),
                          data.unit,
                        )
                      : null,
                  gridColor: DesignConstants.line,
                  surfaceColor: DesignConstants.backgroundColor,
                  labelStyle: DesignConstants.pSmallSemibold.copyWith(
                    color: DesignConstants.text,
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final note in notes) ChartNote(text: note),
      ],
    );

    return ChartWithCompanionTable(
      chart: chart,
      table: data.table,
      granularity: data.granularity,
    );
  }

  /// The good half keeps the positive tone, the bad half the negative one.
  /// Colour here is redundant reinforcement — position already separates
  /// the two — which is exactly why it is safe to use green and red.
  List<DrawnSeries> _divergingColors(List<DrawnSeries> series) => [
        for (var i = 0; i < series.length; i++)
          DrawnSeries(
            key: series[i].key,
            label: series[i].label,
            color: i == 0
                ? DesignConstants.goodGreen
                : DesignConstants.badRed,
            values: series[i].values,
          ),
      ];

  double _newestTotal(SeriesBundle bundle) {
    final last = bundle.dates.length - 1;
    var total = 0.0;
    for (final s in bundle.series) {
      final v = last < s.values.length ? s.values[last] : null;
      if (v != null && v > 0) total += v;
    }
    return total;
  }
}
