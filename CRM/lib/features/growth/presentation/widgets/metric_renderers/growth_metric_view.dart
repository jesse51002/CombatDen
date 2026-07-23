import 'package:flutter/material.dart';

import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/bars_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/breakdown_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/donut_pair_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/hero_split_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/heatmap_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/kpi_group_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/line_view.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/member_list_view.dart';

/// Renders one metric's BODY with the renderer its payload names.
///
/// The section chrome around it — the title, the window subtitle, the
/// hairline between sections — belongs to the page; this widget owns
/// everything inside the section: the marks, the legend, the axes, the
/// hover read-out, and the metric's own empty state.
///
/// The switch is over the SEALED [GrowthMetricData], and is exhaustive on
/// purpose: adding a ninth payload type is then a compile error here rather
/// than a silently blank section on someone's Growth page.
class GrowthMetricView extends StatelessWidget {
  final GrowthMetric metric;

  /// The class chip the page has selected, for metrics carrying `by_class`.
  /// Null (the default) renders the metric's overall series.
  final String? classId;

  const GrowthMetricView({
    super.key,
    required this.metric,
    this.classId,
  });

  @override
  Widget build(BuildContext context) {
    final key = metric.key;
    final name = metric.name;
    return switch (metric.data) {
      KpiGroupData data =>
        KpiGroupView(data: data, metricKey: key, name: name),
      HeroSplitData data =>
        HeroSplitView(data: data, metricKey: key, name: name),
      LineData data => LineView(
          data: data,
          metricKey: key,
          name: name,
          classId: classId,
        ),
      BarsData data => BarsView(
          data: data,
          metricKey: key,
          name: name,
          classId: classId,
        ),
      BreakdownData data =>
        BreakdownView(data: data, metricKey: key, name: name),
      DonutPairData data =>
        DonutPairView(data: data, metricKey: key, name: name),
      HeatmapData data => HeatmapView(
          data: data,
          metricKey: key,
          name: name,
          classId: classId,
        ),
      MemberListData data =>
        MemberListView(data: data, metricKey: key, name: name),
    };
  }
}
