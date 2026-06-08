import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

part 'sweep_painter.dart';

/// The app's shared loading indicator — **"Sweep"**: a faint hairline ring
/// with a single sapphire → accent-dark gradient arc that orbits it,
/// lengthening as it accelerates and shrinking as it eases. The brand's
/// donut / progress-arc motif set in motion — one calm sapphire voice, no
/// bounce. The trailing edge fades to nothing (a comet), the leading edge
/// deepens.
///
/// Drop-in everywhere a small in-place loader is needed; defaults to
/// [DesignConstants.iconSizeLarge] (24) so existing call sites are
/// unchanged. Honors reduced-motion: renders a static resting arc and runs
/// no animation when the OS asks for less motion.
class AppSpinner extends StatefulWidget {
  const AppSpinner({super.key, this.size, this.strokeWidth});

  /// Outer diameter. Defaults to [DesignConstants.iconSizeLarge].
  final double? size;

  /// Stroke width of the arc + track. Defaults to ~1/9 of the diameter.
  final double? strokeWidth;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner>
    with SingleTickerProviderStateMixin {
  // One calm revolution-plus per cycle.
  static const _period = Duration(milliseconds: 1400);

  // The resting phase shown under reduced motion — the peak-breath
  // frame, a full, deliberate gradient arc.
  static const _staticPhase = 0.5;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion && (reduce || _ctrl.isAnimating)) {
      return;
    }
    _reduceMotion = reduce;
    if (reduce) {
      _ctrl.stop();
    } else {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size ?? DesignConstants.iconSizeLarge;
    final stroke = widget.strokeWidth ?? size / 9;
    return SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              painter: _SweepPainter(
                t: _reduceMotion ? _staticPhase : _ctrl.value,
                stroke: stroke,
                arc: DesignConstants.primaryColor,
                arcDeep: DesignConstants.accentDark,
                track: DesignConstants.divider,
              ),
            );
          },
        ),
      ),
    );
  }
}

