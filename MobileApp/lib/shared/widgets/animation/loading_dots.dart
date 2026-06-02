import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// Three brand-colored dots bouncing in a continuous wave — the Airbnb /
/// Linear / Vercel "..." loader. Each dot is offset by 1/3 of a cycle, so
/// the wave reads as a single ripple traveling left-to-right and back.
/// Loops indefinitely; the parent decides when to swap it out.
class LoadingDots extends StatefulWidget {
  const LoadingDots({
    super.key,
    this.dotSize = 24,
    this.spacing = 16,
    this.bounceHeight = 28,
    this.cycleDuration = const Duration(milliseconds: 1100),
    this.value,
  });

  final double dotSize;
  final double spacing;
  final double bounceHeight;
  final Duration cycleDuration;

  /// When null (the default, used everywhere in the app) the dots animate
  /// themselves on a repeating controller. When set (0..1), the wave is rendered
  /// at exactly that phase instead — the capture harness (`tools/capture/`)
  /// drives this per frame so the exported clip plays at true speed.
  final double? value;

  @override
  State<LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<LoadingDots>
    with SingleTickerProviderStateMixin {
  static const int _kDotCount = 3;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.cycleDuration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = DesignConstants.primaryColor;
    final width = _kDotCount * widget.dotSize +
        (_kDotCount - 1) * widget.spacing;
    final height = widget.dotSize + widget.bounceHeight;
    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final v = widget.value ?? _ctrl.value;
          return Stack(
            children: [
              for (int i = 0; i < _kDotCount; i++) _dot(i, brand, v),
            ],
          );
        },
      ),
    );
  }

  Widget _dot(int index, Color color, double cycleValue) {
    final phase = (cycleValue + index / _kDotCount) % 1.0;
    // Half-sine bounce: 0 at rest → 1 at peak → 0 at rest.
    final wave = math.max(0.0, math.sin(phase * 2 * math.pi));
    final left = index * (widget.dotSize + widget.spacing);
    final dy = -wave * widget.bounceHeight;
    return Positioned(
      left: left,
      bottom: 0,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Container(
          width: widget.dotSize,
          height: widget.dotSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
