import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Axis maths shared by the `line` and `bars` renderers: the "nice" ceiling
/// the y-axis rounds up to, the x-axis bucket labels, and which of those
/// labels survive decimation at the plot's current width.

/// The width one x-axis label slot reserves. Drives both the decimation rule
/// (`plotWidth / _labelSlot` labels fit) and the label's own box, so a label
/// centred on its bucket never collides with its neighbour.
const double kXLabelSlot = 56;

/// Rounds [max] up to the next 1 / 2 / 2.5 / 5 x 10^k, so a tick ladder
/// always lands on a readable number. Returns 1 for a non-positive max, so a
/// flat all-zero series still gets a drawable scale.
double niceCeiling(double max) {
  if (!max.isFinite || max <= 0) return 1;
  final exponent = (math.log(max) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final normalized = max / magnitude;
  for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (normalized <= step + 1e-9) return step * magnitude;
  }
  return 10 * magnitude;
}

/// The three y ticks, top to bottom: max, max/2, 0.
List<double> yTicksFor(double niceMax) => [niceMax, niceMax / 2, 0];

/// The short x-axis label for a bucket's ISO [date] at [granularity].
///
/// `month` reads `Feb'25`; `week` / `day` read `Jun 2`; the newest bucket of
/// a weekly series reads `This wk` (it is the incomplete one).
String bucketLabel(String date, String granularity, {bool isNewest = false}) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  if (granularity == 'month') return DateFormat("MMM''yy").format(parsed);
  if (isNewest && granularity == 'week') return 'This wk';
  return DateFormat.MMMd().format(parsed);
}

/// The long form used by the hover read-out, where there is room to be exact.
String bucketLabelLong(String date, String granularity) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  if (granularity == 'month') return DateFormat.yMMM().format(parsed);
  if (granularity == 'week') {
    return 'Week of ${DateFormat.yMMMd().format(parsed)}';
  }
  return DateFormat.yMMMd().format(parsed);
}

/// The bucket indices whose label survives at [plotWidth].
///
/// Samples evenly and ALWAYS keeps the first and last bucket, so the axis
/// never loses either end of the window.
Set<int> visibleLabelIndices(int bucketCount, double plotWidth) {
  if (bucketCount <= 0) return const {};
  if (bucketCount == 1) return {0};
  final fits = (plotWidth / kXLabelSlot).floor().clamp(2, bucketCount);
  if (fits >= bucketCount) {
    return {for (var i = 0; i < bucketCount; i++) i};
  }
  final indices = <int>{0, bucketCount - 1};
  final step = (bucketCount - 1) / (fits - 1);
  for (var i = 1; i < fits - 1; i++) {
    indices.add((i * step).round());
  }
  return indices;
}
