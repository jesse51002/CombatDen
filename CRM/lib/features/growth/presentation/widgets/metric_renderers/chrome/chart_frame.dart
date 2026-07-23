import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/chart_scale.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';

/// The frame every time-series chart sits in: the y-axis tick column on the
/// LEFT (reading-order convention), the plot at [DesignConstants.heroChartHeight],
/// and the decimated x-axis label row beneath it.
///
/// The outer column is never height-capped, so an x label can never be
/// clipped into a nested scroll.
class ChartFrame extends StatelessWidget {
  /// Tick values top to bottom (max, max/2, 0).
  final List<double> yTicks;
  final MetricUnit unit;

  /// Bucket dates in wire order — one x label candidate each.
  final List<String> dates;
  final String granularity;

  /// Centre x of a bucket, shared with the painter and the hover layer.
  final double Function(int index, double plotWidth) xOf;

  /// The painted plot (already wrapped in its hover layer).
  final Widget plot;

  const ChartFrame({
    super.key,
    required this.yTicks,
    required this.unit,
    required this.dates,
    required this.granularity,
    required this.xOf,
    required this.plot,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        SizedBox(
          height: DesignConstants.heroChartHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final tick in yTicks)
                Text(
                  formatAxisTick(tick, unit),
                  style: DesignConstants.pSmall.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingMedium,
            children: [
              SizedBox(
                height: DesignConstants.heroChartHeight,
                child: plot,
              ),
              _XAxisLabels(
                dates: dates,
                granularity: granularity,
                xOf: xOf,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _XAxisLabels extends StatelessWidget {
  final List<String> dates;
  final String granularity;
  final double Function(int index, double plotWidth) xOf;

  const _XAxisLabels({
    required this.dates,
    required this.granularity,
    required this.xOf,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final visible = visibleLabelIndices(dates.length, width);
        return SizedBox(
          height: DesignConstants.spacingLarge,
          child: Stack(
            children: [
              for (final i in visible)
                Positioned(
                  left: (xOf(i, width) - kXLabelSlot / 2)
                      .clamp(0.0, (width - kXLabelSlot).clamp(0.0, width)),
                  top: 0,
                  width: kXLabelSlot,
                  child: Text(
                    bucketLabel(
                      dates[i],
                      granularity,
                      isNewest: i == dates.length - 1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignConstants.pSmall.copyWith(
                      color: DesignConstants.text3rd,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
