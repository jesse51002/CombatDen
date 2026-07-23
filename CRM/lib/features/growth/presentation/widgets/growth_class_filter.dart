import 'package:crm/features/growth/data/models/growth_metric.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// One selectable class on the Attendance tab.
class GrowthClassOption {
  final String classId;
  final String className;

  const GrowthClassOption({required this.classId, required this.className});
}

/// Every class the tab's metrics carry a `by_class` slice for, in wire
/// order, de-duplicated by id.
///
/// The chip list is derived from the DATA rather than from the gym's class
/// catalog: a chip that no metric can answer would filter every section
/// down to its fallback and read as a bug.
List<GrowthClassOption> classOptionsFor(Iterable<GrowthMetric> metrics) {
  final options = <GrowthClassOption>[];
  final seen = <String>{};

  void add(String classId, String className) {
    if (seen.add(classId)) {
      options.add(GrowthClassOption(classId: classId, className: className));
    }
  }

  for (final metric in metrics) {
    switch (metric.data) {
      case final LineData data:
        for (final c in data.byClass ?? const <ClassSeries>[]) {
          add(c.classId, c.className);
        }
      case final BarsData data:
        for (final c in data.byClass ?? const <ClassSeries>[]) {
          add(c.classId, c.className);
        }
      case final HeatmapData data:
        for (final c in data.byClass ?? const <ClassHeatmap>[]) {
          add(c.classId, c.className);
        }
      default:
        break;
    }
  }
  return options;
}

/// Whether [metric] carries a `by_class` slice for [classId] — i.e. whether
/// the class selection actually changes what this section shows.
bool metricCarriesClass(GrowthMetric metric, String classId) {
  switch (metric.data) {
    case final LineData data:
      return data.byClass?.any((c) => c.classId == classId) ?? false;
    case final BarsData data:
      return data.byClass?.any((c) => c.classId == classId) ?? false;
    case final HeatmapData data:
      return data.byClass?.any((c) => c.classId == classId) ?? false;
    default:
      return false;
  }
}
