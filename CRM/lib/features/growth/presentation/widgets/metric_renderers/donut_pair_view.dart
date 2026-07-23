import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/shared/widgets/empty_state.dart';
import 'package:crm/shared/widgets/progress_arc.dart';

/// Renders a `donut_pair` metric: the live period beside its benchmark.
///
/// The live donut takes the accent, the benchmark takes the residual gray —
/// two identical accent rings would hide which of the two is the yardstick.
class DonutPairView extends StatelessWidget {
  final DonutPairData data;
  final String metricKey;
  final String name;

  const DonutPairView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final donuts = data.donuts.where((d) => !d.pct.isNaN).toList();
    if (donuts.isEmpty) {
      return const EmptyState.inline(
        icon: Symbols.donut_large_sharp,
        title: 'Not enough history yet',
        body: 'Needs at least one full month of members to compare against.',
      );
    }
    if (donuts.length > 2) {
      log('DonutPairView: "$metricKey" served ${donuts.length} donuts; '
          'rendering the first two');
    }
    final drawn = donuts.take(2).toList();

    return Center(
      child: Wrap(
        spacing: DesignConstants.spacingBig,
        runSpacing: DesignConstants.spacingBig,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < drawn.length; i++)
            _Donut(
              spec: drawn[i],
              color: i == 0
                  ? DesignConstants.primaryColor
                  : DesignConstants.text3rd,
            ),
        ],
      ),
    );
  }
}

class _Donut extends StatelessWidget {
  final DonutSpec spec;
  final Color color;

  const _Donut({required this.spec, required this.color});

  @override
  Widget build(BuildContext context) {
    final headline = formatMetricValue(spec.pct, MetricUnit.percent);
    return Semantics(
      label: spec.label,
      value: headline,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          SizedBox(
            height: DesignConstants.heroChartHeight,
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProgressArc(
                    progress: spec.pct / 100,
                    progressColor: color,
                    // The de-carded ground needs the hairline track; the
                    // default card colour would paint a white ring on it.
                    trackColor: DesignConstants.line,
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DesignConstants.spacingSmall,
                      children: [
                        Text(headline, style: DesignConstants.big2Bold),
                        Text(
                          spec.label,
                          textAlign: TextAlign.center,
                          style: DesignConstants.p.copyWith(
                            color: DesignConstants.text2nd,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (spec.caption != null)
            Text(
              spec.caption!,
              textAlign: TextAlign.center,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text3rd,
              ),
            ),
        ],
      ),
    );
  }
}
