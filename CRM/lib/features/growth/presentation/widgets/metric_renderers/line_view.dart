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
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/series_line_painter.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/series/drawn_series.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// Renders a `line` metric: one to three time series as smooth splines over
/// a left-hand y axis and a decimated x-axis label row.
///
/// Series count changes the chrome: one series gets its area wash and its
/// direct end label (the section title already names it), two get a legend
/// and both end labels, three get a legend and only S1 end-labelled.
class LineView extends StatelessWidget {
  final LineData data;
  final String metricKey;
  final String name;

  /// The selected class chip, when the metric carries `by_class`.
  final String? classId;

  const LineView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
    this.classId,
  });

  @override
  Widget build(BuildContext context) {
    final bundle = buildSeriesBundle(
      seriesForClass(data.series, data.byClass, classId),
    );
    if (bundle.isEmpty) {
      return EmptyState.inline(
        icon: Symbols.show_chart_sharp,
        title: 'No $name history yet',
        body: 'This fills in as the gym records data. Check back after '
            'your first full month.',
      );
    }

    final series = bundle.series;
    final niceMax = niceCeiling(bundle.maxValue);
    final ticks = yTicksFor(niceMax);
    final singlePoint = bundle.dates.length < 2;

    final endLabels = <int, String>{};
    for (var i = 0; i < series.length; i++) {
      final last = series[i].lastValue;
      if (last != null) {
        endLabels[i] = formatMetricValue(last, data.unit);
      }
    }
    // 1 series: label it. 2: label both unless they collide (the painter
    // drops a crowded pair). 3: only the accent series.
    final endLabeled = series.length == 2 ? {0, 1} : {0};

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
            xOf: (i, width) => lineXOf(i, bundle.dates.length, width),
            plot: ChartHoverLayer(
              bucketCount: bundle.dates.length,
              xOf: (i, width) => lineXOf(i, bundle.dates.length, width),
              readoutFor: (i) => seriesReadout(
                bundle: bundle,
                index: i,
                unit: data.unit,
                granularity: data.granularity,
              ),
              child: CustomPaint(
                size: Size.infinite,
                painter: SeriesLinePainter(
                  series: series,
                  maxY: niceMax,
                  gridTicks: ticks,
                  areaFill: series.length == 1,
                  endLabeled: endLabeled,
                  endLabels: endLabels,
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
        if (singlePoint) const ChartNote(text: 'Only one period so far'),
      ],
    );

    return ChartWithCompanionTable(chart: chart, table: data.table);
  }
}
