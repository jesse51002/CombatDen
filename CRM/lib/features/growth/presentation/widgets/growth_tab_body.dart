import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/bloc/growth_state.dart';
import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/presentation/widgets/growth_class_filter.dart';
import 'package:crm/features/growth/presentation/widgets/growth_metric_registry.dart';
import 'package:crm/features/growth/presentation/widgets/growth_range.dart';
import 'package:crm/features/growth/presentation/widgets/growth_section.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/growth_metric_view.dart';
import 'package:crm/shared/widgets/empty_state.dart';
import 'package:crm/shared/widgets/hairline.dart';

/// One Growth tab: every metric tagged with [category], in envelope order,
/// as hairline-separated de-carded sections.
///
/// The tab owns no data of its own — one backend read serves all six tabs,
/// and the range / class filters are pure client-side reshapes applied on
/// the way into each renderer.
class GrowthTabBody extends StatelessWidget {
  final GrowthState state;
  final GrowthCategory category;

  /// The page's time window; trims `line` / `bars` series only.
  final GrowthRange range;

  /// The selected class chip (Attendance only), or null for all classes.
  final String? classId;

  /// The selected class's display name, for the section subtitle.
  final String? className;

  /// Below `navMobileBreakpoint`: every half-span section renders full.
  final bool compact;

  const GrowthTabBody({
    super.key,
    required this.state,
    required this.category,
    required this.range,
    this.classId,
    this.className,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = state.metricsIn(category);
    final body = metrics.isEmpty
        ? const EmptyState(
            icon: Symbols.query_stats_sharp,
            title: 'Nothing to show on this tab yet',
            body: 'These metrics appear once your gym has the activity '
                'behind them.',
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DesignConstants.spacingBig,
            children: _rows(metrics),
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.paddingBig,
      ),
      child: body,
    );
  }

  /// The tab's rows, hairline-separated. Two consecutive half-span metrics
  /// pair into one row; a half with no half neighbour renders full.
  List<Widget> _rows(List<GrowthMetric> metrics) {
    final rows = <Widget>[];
    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      final next = i + 1 < metrics.length ? metrics[i + 1] : null;
      final pairs = !compact &&
          next != null &&
          metricSpan(metric) == MetricSpan.half &&
          metricSpan(next) == MetricSpan.half;
      if (pairs) {
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DesignConstants.spacingBig,
              children: [
                Expanded(child: _section(metric)),
                const Hairline(vertical: true),
                Expanded(child: _section(next)),
              ],
            ),
          ),
        );
        i++;
      } else {
        rows.add(_section(metric));
      }
    }

    // A hairline between rows — never above the first or below the last.
    final withRules = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) withRules.add(const Hairline());
      withRules.add(rows[i]);
    }
    return withRules;
  }

  Widget _section(GrowthMetric metric) {
    final trimmed = trimMetricToRange(metric, range);
    return GrowthSection(
      title: metric.name,
      subtitle: _subtitleFor(metric),
      child: GrowthMetricView(metric: trimmed, classId: classId),
    );
  }

  /// The section's window line: its registered window, replaced by the
  /// range pill's window when the pill actually trimmed this metric, and
  /// suffixed with the class when the class chip actually narrowed it.
  ///
  /// Stating the real window per section is what keeps a filter honest —
  /// a snapshot metric sitting under a "3M" pill must not look filtered.
  String _subtitleFor(GrowthMetric metric) {
    final trimmedWindow = range.windowLabel;
    var label = metricHasSeries(metric) && trimmedWindow != null
        ? trimmedWindow
        : metricWindowLabel(metric.key);

    final selectedId = classId;
    final selectedName = className;
    if (selectedId != null &&
        selectedName != null &&
        metricCarriesClass(metric, selectedId)) {
      label = label.isEmpty ? selectedName : '$label · $selectedName';
    }
    return label;
  }
}
