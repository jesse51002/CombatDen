import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/chrome/chart_readout_card.dart';

/// Wraps a painted plot with a mouse-driven per-bucket read-out.
///
/// This is Flutter **web**, mouse-first: a [MouseRegion] hit-tests the
/// pointer against the SAME geometry the painter used ([xOf]), resolves the
/// nearest bucket, and draws a hairline crosshair plus a [ChartReadoutCard].
/// The resolve runs on hover — never inside the paint loop — and only calls
/// `setState` when the resolved bucket actually changes, so dragging the
/// pointer along a chart repaints once per bucket, not once per pixel.
class ChartHoverLayer extends StatefulWidget {
  final int bucketCount;

  /// Centre x of bucket [index] inside a plot [plotWidth] wide — the same
  /// formula the painter lays its marks out with.
  final double Function(int index, double plotWidth) xOf;

  /// The read-out for a bucket, built lazily on hover.
  final ChartReadout Function(int index) readoutFor;

  /// The painted plot.
  final Widget child;

  const ChartHoverLayer({
    super.key,
    required this.bucketCount,
    required this.xOf,
    required this.readoutFor,
    required this.child,
  });

  @override
  State<ChartHoverLayer> createState() => _ChartHoverLayerState();
}

class _ChartHoverLayerState extends State<ChartHoverLayer> {
  int? _hovered;

  void _onHover(Offset local, double plotWidth) {
    if (widget.bucketCount == 0 || plotWidth <= 0) return;
    var nearest = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < widget.bucketCount; i++) {
      final distance = (widget.xOf(i, plotWidth) - local.dx).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = i;
      }
    }
    if (nearest != _hovered) setState(() => _hovered = nearest);
  }

  void _clear() {
    if (_hovered != null) setState(() => _hovered = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final hovered = _hovered;
        return MouseRegion(
          onHover: (event) => _onHover(event.localPosition, width),
          onExit: (_) => _clear(),
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              if (hovered != null && hovered < widget.bucketCount)
                ..._overlay(hovered, width),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _overlay(int index, double width) {
    final x = widget.xOf(index, width);
    final left = (x - ChartReadoutCard.maxWidth / 2)
        .clamp(0.0, (width - ChartReadoutCard.maxWidth).clamp(0.0, width));
    return [
      Positioned(
        left: x - DesignConstants.dividerThickness / 2,
        top: 0,
        bottom: 0,
        width: DesignConstants.dividerThickness,
        child: ColoredBox(color: DesignConstants.line),
      ),
      Positioned(
        left: left,
        top: DesignConstants.spacingMedium,
        child: ChartReadoutCard(readout: widget.readoutFor(index)),
      ),
    ];
  }
}
