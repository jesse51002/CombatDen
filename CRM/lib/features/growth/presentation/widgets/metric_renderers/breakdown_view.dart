import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/models/growth_metric_data.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/format/metric_value_format.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// Past this many rows a breakdown stops being a comparison; the tail sums
/// into one residual row.
const int kMaxBreakdownItems = 8;

/// Renders a `breakdown` metric: horizontal category bars with the value on
/// the row itself. No plot frame and no axis — the row IS the axis.
class BreakdownView extends StatelessWidget {
  final BreakdownData data;
  final String metricKey;
  final String name;

  const BreakdownView({
    super.key,
    required this.data,
    required this.metricKey,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    if (data.items.isEmpty) {
      return EmptyState.inline(
        icon: Symbols.bar_chart_sharp,
        title: 'No $name to show',
        body: 'Categories appear here once members are assigned to them.',
      );
    }

    final items = _foldTail(data.items);
    // A percent bar is absolute: 39% fills 39% of the track, never "the
    // smallest of these four". Everything else is relative to the biggest
    // row, because the unit has no natural ceiling.
    final max = items.fold<double>(
      0,
      (best, item) => item.value > best ? item.value : best,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final item in items)
          _BreakdownRow(
            item: item,
            unit: data.unit,
            fraction: data.unit == MetricUnit.percent
                ? (item.value / 100).clamp(0.0, 1.0)
                : (max > 0 ? (item.value / max).clamp(0.0, 1.0) : 0.0),
          ),
      ],
    );
  }

  /// Keeps wire order — the backend sorts (descending for nominal buckets,
  /// natural order for ordinal ones like belts), and re-sorting here is what
  /// would break the next metric that drops in.
  List<BreakdownItem> _foldTail(List<BreakdownItem> items) {
    if (items.length <= kMaxBreakdownItems) return items;
    final head = items.take(kMaxBreakdownItems - 1).toList();
    final tail = items.skip(kMaxBreakdownItems - 1);
    final total = tail.fold<double>(0, (sum, item) => sum + item.value);
    return [
      ...head,
      BreakdownItem(key: 'other', label: 'Other', value: total),
    ];
  }
}

class _BreakdownRow extends StatelessWidget {
  final BreakdownItem item;
  final MetricUnit unit;
  final double fraction;

  const _BreakdownRow({
    required this.item,
    required this.unit,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final value = formatMetricValue(item.value, unit);
    // The row prints its own value; the hover read-out is the exact same
    // pairing for a pointer resting on the bar.
    return Tooltip(
      message: '${item.label}: $value',
      waitDuration: Duration.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DesignConstants.spacingSmall,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignConstants.h3,
                ),
              ),
              Text(value, style: DesignConstants.h3),
            ],
          ),
          _Track(fraction: fraction, fill: _fillColor(item)),
        ],
      ),
    );
  }

  /// The one breakdown with data-owned colour: a rank's own belt colour when
  /// the wire supplies one. Every other bar takes slot 1 — bar length
  /// already encodes magnitude, and re-encoding it in hue would burn the
  /// identity channel for nothing.
  Color _fillColor(BreakdownItem item) =>
      _parseColorHint(item.colorHint) ?? DesignConstants.primaryColor;
}

class _Track extends StatelessWidget {
  final double fraction;
  final Color fill;

  const _Track({required this.fraction, required this.fill});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DesignConstants.radiusSmall);
    return SizedBox(
      height: DesignConstants.spacingMedium,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DesignConstants.line,
                borderRadius: radius,
              ),
            ),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            // heightFactor is load-bearing: without it the fill's child gets
            // the Stack's loose height (min 0) and, having no intrinsic
            // height, collapses to zero — the track shows but the coloured
            // fill is invisible. Pin it to the full track height.
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parses a wire colour hint (`#RRGGBB`, `#AARRGGBB`, or either without the
/// hash). Returns null for anything unparseable, so a bad hint falls back to
/// the accent rather than throwing.
Color? _parseColorHint(String? hint) {
  if (hint == null) return null;
  var value = hint.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
