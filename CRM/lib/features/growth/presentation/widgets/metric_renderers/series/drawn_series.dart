import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// One series as the painters want it: a label, a colour, and one value per
/// bucket (null where that series has no point for the bucket).
@immutable
class DrawnSeries {
  final String key;
  final String label;
  final Color color;
  final List<double?> values;

  const DrawnSeries({
    required this.key,
    required this.label,
    required this.color,
    required this.values,
  });

  /// The newest bucket that carries a value, or null when the series is empty.
  double? get lastValue {
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] != null) return values[i];
    }
    return null;
  }

  /// The newest bucket index carrying a value, or -1 when there is none.
  int get lastIndex {
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] != null) return i;
    }
    return -1;
  }

  // Value equality (not identity) so a painter holding a list of these can
  // answer `shouldRepaint` correctly.
  @override
  bool operator ==(Object other) =>
      other is DrawnSeries &&
      other.key == key &&
      other.label == label &&
      other.color == color &&
      listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(key, label, color, Object.hashAll(values));
}

/// The bucket axis plus the (at most three) series drawn against it.
@immutable
class SeriesBundle {
  /// The bucket dates, ISO strings in wire order.
  final List<String> dates;
  final List<DrawnSeries> series;

  /// True when four or more wire series were folded into one `Other`.
  final bool folded;

  const SeriesBundle({
    required this.dates,
    required this.series,
    required this.folded,
  });

  bool get isEmpty => dates.isEmpty || series.isEmpty;

  /// The largest value drawn anywhere, 0 when nothing is drawn.
  double get maxValue {
    var max = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v != null && v > max) max = v;
      }
    }
    return max;
  }

  /// The newest [count] buckets, or this bundle when it is already shorter.
  ///
  /// A bar chart past ~40 buckets is a smear; the range pill is the real
  /// control, so the chart keeps the newest window and says so.
  SeriesBundle takeNewest(int count) {
    if (dates.length <= count) return this;
    final from = dates.length - count;
    return SeriesBundle(
      dates: dates.sublist(from),
      series: [
        for (final s in series)
          DrawnSeries(
            key: s.key,
            label: s.label,
            color: s.color,
            values: s.values.length > from
                ? s.values.sublist(from)
                : List<double?>.filled(count, null),
          ),
      ],
      folded: folded,
    );
  }

  /// The largest per-bucket TOTAL — the ceiling a stacked chart needs.
  double get maxStackedValue {
    var max = 0.0;
    for (var i = 0; i < dates.length; i++) {
      var sum = 0.0;
      for (final s in series) {
        final v = i < s.values.length ? s.values[i] : null;
        if (v != null && v > 0) sum += v;
      }
      if (sum > max) max = sum;
    }
    return max;
  }
}

/// The ordinal ramp: S1 (the outcome), S2 (its companion), then the residual
/// slot. Never generates a hue and never cycles — a fourth series is folded
/// into `Other` before it can ask for a colour.
Color seriesColor(int index) => switch (index) {
      0 => DesignConstants.primaryColor,
      1 => DesignConstants.darkPrimary,
      _ => DesignConstants.text3rd,
    };

/// Builds the bucket axis + drawn series from the wire series.
///
/// Buckets come from the union of every series' dates, ordered by the
/// richest series so a short series aligns against the full window. Four or
/// more series fold: S1 and S2 survive, everything after is summed into one
/// `Other` (merging with a wire `Other` when there is one).
SeriesBundle buildSeriesBundle(List<MetricSeries> wire) {
  final nonEmpty = wire.where((s) => s.points.isNotEmpty).toList();
  if (nonEmpty.isEmpty) {
    return const SeriesBundle(dates: [], series: [], folded: false);
  }

  final dates = _bucketDates(nonEmpty);
  final index = {for (var i = 0; i < dates.length; i++) dates[i]: i};

  List<double?> valuesOf(MetricSeries s) {
    final values = List<double?>.filled(dates.length, null);
    for (final p in s.points) {
      final at = index[p.date];
      if (at != null) values[at] = p.value;
    }
    return values;
  }

  final folded = nonEmpty.length > 3;
  if (!folded) {
    return SeriesBundle(
      dates: dates,
      series: [
        for (var i = 0; i < nonEmpty.length; i++)
          DrawnSeries(
            key: nonEmpty[i].key,
            label: nonEmpty[i].label,
            color: seriesColor(i),
            values: valuesOf(nonEmpty[i]),
          ),
      ],
      folded: false,
    );
  }

  final kept = nonEmpty.take(2).toList();
  final rest = nonEmpty.skip(2).toList();
  // A wire "Other" absorbs the fold instead of sitting beside a second one.
  final wireOther = rest.where((s) => s.key == 'other').toList();
  final residual = List<double?>.filled(dates.length, null);
  for (final s in rest) {
    final values = valuesOf(s);
    for (var i = 0; i < dates.length; i++) {
      final v = values[i];
      if (v == null) continue;
      residual[i] = (residual[i] ?? 0) + v;
    }
  }

  return SeriesBundle(
    dates: dates,
    series: [
      for (var i = 0; i < kept.length; i++)
        DrawnSeries(
          key: kept[i].key,
          label: kept[i].label,
          color: seriesColor(i),
          values: valuesOf(kept[i]),
        ),
      DrawnSeries(
        key: 'other',
        label: wireOther.isNotEmpty ? wireOther.first.label : 'Other',
        color: seriesColor(2),
        values: residual,
      ),
    ],
    folded: true,
  );
}

List<String> _bucketDates(List<MetricSeries> series) {
  var richest = series.first;
  for (final s in series) {
    if (s.points.length > richest.points.length) richest = s;
  }
  final dates = <String>[for (final p in richest.points) p.date];
  final seen = dates.toSet();
  for (final s in series) {
    for (final p in s.points) {
      if (seen.add(p.date)) dates.add(p.date);
    }
  }
  return dates;
}

/// The series to draw for the selected class chip: the class's own series
/// when [classId] names one, the metric's overall series otherwise.
List<MetricSeries> seriesForClass(
  List<MetricSeries> base,
  List<ClassSeries>? byClass,
  String? classId,
) {
  if (classId == null || byClass == null) return base;
  for (final c in byClass) {
    if (c.classId == classId) return c.series;
  }
  return base;
}

/// The heatmap grid for the selected class chip, falling back to the
/// metric's overall grid.
List<List<double?>> cellsForClass(
  List<List<double?>> base,
  List<ClassHeatmap>? byClass,
  String? classId,
) {
  if (classId == null || byClass == null) return base;
  for (final c in byClass) {
    if (c.classId == classId) return c.cells;
  }
  return base;
}
