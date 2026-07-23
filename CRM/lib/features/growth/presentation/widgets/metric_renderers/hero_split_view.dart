import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_legend.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/hero_split_painter.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// The colour for one hero segment: its declared tone, else the ordinal
/// ramp by position.
///
/// `neutral` / `pending` take the residual gray deliberately — an
/// "Expected" slice is not money yet, and the deep sapphire that would
/// otherwise sit in slot 2 measures too close to the accent in light mode
/// to carry a peer identity beside it.
Color heroSegmentColor(String? tone, int index) => switch (tone) {
      'accent' => DesignConstants.primaryColor,
      'good' => DesignConstants.goodGreen,
      'warn' => DesignConstants.okYellow,
      'bad' => DesignConstants.badRed,
      'neutral' || 'pending' => DesignConstants.text3rd,
      _ => switch (index) {
          0 => DesignConstants.primaryColor,
          1 => DesignConstants.darkPrimary,
          _ => DesignConstants.text3rd,
        },
    };

/// Renders a `hero_split` metric — the page's one hero figure: a half-pie
/// of N segments with the unit-aware total in its centre and a legend that
/// carries each segment's own value.
class HeroSplitView extends StatelessWidget {
  final HeroSplitData data;
  final String metricKey;
  final String name;

  const HeroSplitView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    final segments = data.segments;
    final drawn = segments.where((s) => s.value > 0).toList();
    final isEmpty = drawn.isEmpty || data.total <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: [
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(
                constraints.maxWidth,
                DesignConstants.heroChartHeight * 2,
              );
              return SizedBox(
                width: width,
                height: width / 2,
                child: Semantics(
                  label: name,
                  value: _summary(),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: HeroSplitPainter(
                            values: [for (final s in segments) s.value],
                            colors: [
                              for (var i = 0; i < segments.length; i++)
                                heroSegmentColor(segments[i].tone, i),
                            ],
                            trackColor: DesignConstants.line,
                          ),
                        ),
                      ),
                      _CentreLabel(
                        total: formatMetricValue(data.total, data.unit),
                        caption: data.caption,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (isEmpty)
          const EmptyState.inline(
            icon: Symbols.payments_sharp,
            title: 'Nothing billed this month yet',
            body: 'Collected, expected and overdue amounts appear once '
                'invoices go out.',
            minHeight: 0,
          )
        else
          ChartLegend(
            center: true,
            entries: [
              for (var i = 0; i < segments.length; i++)
                if (segments[i].value > 0)
                  ChartLegendEntry(
                    color: heroSegmentColor(segments[i].tone, i),
                    label: '${segments[i].label} '
                        '${formatMetricValue(segments[i].value, data.unit)}',
                  ),
            ],
          ),
      ],
    );
  }

  String _summary() {
    final total = formatMetricValue(data.total, data.unit);
    final parts = [
      for (final s in data.segments)
        '${s.label} ${formatMetricValue(s.value, data.unit)}',
    ];
    return parts.isEmpty ? total : '$total — ${parts.join(', ')}';
  }
}

class _CentreLabel extends StatelessWidget {
  final String total;
  final String? caption;

  const _CentreLabel({required this.total, this.caption});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignConstants.paddingSmall),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(total, style: DesignConstants.big2Bold),
          if (caption != null)
            Text(
              caption!,
              textAlign: TextAlign.center,
              style: DesignConstants.h2Regular.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
        ],
      ),
    );
  }
}
