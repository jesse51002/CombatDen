import 'package:intl/intl.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';

/// Value formatting for every Growth renderer — one helper, so a KPI tile, a
/// legend entry, an axis tick and a hover read-out never disagree about what
/// the same number looks like.
///
/// [MetricUnit] is the only input that decides the shape:
/// - `cents` — integer minor units on the wire, rendered through the shared
///   money helper (`$9,140`).
/// - `percent` — arrives 0-100, rendered `41%` / `12.4%`.
/// - `count` / `unknown` — a plain grouped number (`1,284`), keeping one
///   decimal for the genuinely fractional counts (an average visit rate).

/// Grouped, at most one fraction digit: `1,284` / `3.2`.
final NumberFormat _plain = NumberFormat('#,##0.#');

/// Exact grouped integer, for axis ticks below the compaction threshold.
final NumberFormat _integer = NumberFormat('#,##0');

/// One decimal, for the compacted `12.4k` / `1.2M` forms.
final NumberFormat _compact = NumberFormat('#,##0.#');

/// Counts compact above this; money compacts above `$1,000`.
const double _compactCountFloor = 10000;
const double _compactDollarFloor = 1000;

/// The formatted value of [value] under [unit].
String formatMetricValue(double value, MetricUnit unit) {
  if (value.isNaN || value.isInfinite) return '—';
  return switch (unit) {
    MetricUnit.cents => formatMinorUnits(value.round(), decimalDigits: 0),
    MetricUnit.percent => '${_plain.format(value)}%',
    MetricUnit.count || MetricUnit.unknown => _plain.format(value),
  };
}

/// The axis-tick form of [value] — the same value, compacted once it stops
/// fitting a tick slot (`12.4k`, `$1.2M`).
String formatAxisTick(double value, MetricUnit unit) {
  if (value.isNaN || value.isInfinite) return '';
  switch (unit) {
    case MetricUnit.percent:
      return '${_plain.format(value)}%';
    case MetricUnit.cents:
      final dollars = value / 100;
      if (dollars.abs() < _compactDollarFloor) {
        return formatMinorUnits(value.round(), decimalDigits: 0);
      }
      return '\$${_compactMagnitude(dollars)}';
    case MetricUnit.count:
    case MetricUnit.unknown:
      if (value.abs() < _compactCountFloor) {
        return _integer.format(value);
      }
      return _compactMagnitude(value);
  }
}

/// `12.4k` / `1.2M` / `3.4B`, sign preserved.
String _compactMagnitude(double value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  if (abs >= 1000000000) return '$sign${_compact.format(abs / 1000000000)}B';
  if (abs >= 1000000) return '$sign${_compact.format(abs / 1000000)}M';
  if (abs >= 1000) return '$sign${_compact.format(abs / 1000)}k';
  return '$sign${_compact.format(abs)}';
}

/// A signed percentage delta, e.g. `+11%` / `-20.5%`.
String formatDeltaPct(double pct) {
  final sign = pct > 0 ? '+' : '';
  return '$sign${_plain.format(pct)}%';
}

/// A signed absolute delta in the tile's own unit, e.g. `+14` / `-$220`.
String formatDeltaAbs(double value, MetricUnit unit) {
  final sign = value > 0 ? '+' : '';
  return '$sign${formatMetricValue(value, unit)}';
}
