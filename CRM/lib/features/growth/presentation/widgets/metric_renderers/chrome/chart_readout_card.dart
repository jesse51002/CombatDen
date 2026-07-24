import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One line of a hover read-out: an optional series swatch, the series name,
/// and its exact value at the hovered bucket.
@immutable
class ChartReadoutLine {
  final Color? swatch;
  final String label;
  final String value;

  const ChartReadoutLine({
    this.swatch,
    required this.label,
    required this.value,
  });
}

/// What the pointer is over: the bucket's own label (its date, or a cell's
/// row/column) and one line per series.
@immutable
class ChartReadout {
  final String title;
  final List<ChartReadoutLine> lines;

  const ChartReadout({required this.title, required this.lines});
}

/// The floating read-out shown while the pointer is over a chart.
///
/// Values stay readable without it (axis ticks, direct end labels, the
/// legend), so this is an enhancement — but on a desktop metrics page a
/// per-bucket read-out is what makes a chart usable.
class ChartReadoutCard extends StatelessWidget {
  final ChartReadout readout;

  /// Ceiling for the card's width; the anchor clamps against it so the card
  /// never leaves the plot.
  static const double maxWidth = 200;

  const ChartReadoutCard({super.key, required this.readout});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.popup,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          border: Border.all(color: DesignConstants.line),
          boxShadow: DesignConstants.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingSmall,
          children: [
            Text(
              readout.title,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text3rd,
              ),
            ),
            for (final line in readout.lines) _ReadoutRow(line: line),
          ],
        ),
      ),
    );
  }
}

class _ReadoutRow extends StatelessWidget {
  final ChartReadoutLine line;

  const _ReadoutRow({required this.line});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        if (line.swatch != null)
          Container(
            width: DesignConstants.spacingMedium,
            height: DesignConstants.spacingMedium,
            decoration: BoxDecoration(
              color: line.swatch,
              shape: BoxShape.circle,
            ),
          ),
        Flexible(
          child: Text(
            line.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignConstants.pSmall.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
        ),
        Text(
          line.value,
          style: DesignConstants.pSmallSemibold.copyWith(
            color: DesignConstants.text,
          ),
        ),
      ],
    );
  }
}
