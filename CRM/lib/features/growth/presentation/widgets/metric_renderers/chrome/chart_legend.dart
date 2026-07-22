import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/intrinsic_wrap.dart';

/// One legend entry — a colour swatch and the label that owns it.
///
/// The label carries the series' VALUE as well as its name
/// (`Collected $7,920`), so identity never depends on matching a colour to a
/// mark. That is the mandatory relief for the two measured colour pairs that
/// sit just under the normal-vision separation floor.
@immutable
class ChartLegendEntry {
  final Color color;
  final String label;

  const ChartLegendEntry({required this.color, required this.label});
}

/// The legend beneath (or beside) a chart. Wraps to further runs rather than
/// overflowing on a narrow viewport.
class ChartLegend extends StatelessWidget {
  final List<ChartLegendEntry> entries;

  /// Centers the runs — the `hero_split` legend sits under a centered arc.
  final bool center;

  const ChartLegend({
    super.key,
    required this.entries,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWrap(
      spacing: DesignConstants.spacingLarge,
      runSpacing: DesignConstants.spacingMedium,
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in entries) _LegendDot(entry: entry),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final ChartLegendEntry entry;

  const _LegendDot({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Container(
          width: DesignConstants.legendDotSize,
          height: DesignConstants.legendDotSize,
          decoration: BoxDecoration(
            color: entry.color,
            shape: BoxShape.circle,
          ),
        ),
        Text(
          entry.label,
          style: DesignConstants.h2Regular.copyWith(
            color: DesignConstants.text,
          ),
        ),
      ],
    );
  }
}
