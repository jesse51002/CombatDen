import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/presentation/widgets/next_rank/rank_arc_painter.dart';

/// The big arc's box and stroke, and the two bar thicknesses.
/// Per-treatment layout math, not fungible design tokens.
const double _kArcSize = 232;
const double _kArcStroke = 10;
const double _kBarHeight = 8;
const double _kRailHeight = 6;

/// How progress toward the next rank is drawn. One element, four
/// treatments — the value shown is identical in every one.
enum NextRankProgressLayout {
  /// A thin arc hugging the belt badge. Ships today.
  ring,

  /// A large ring with the belt inside it.
  arc,

  /// A rounded inline bar.
  bar,

  /// A square-ended full-bleed strip.
  rail,
}

/// How close the member is to the next rank.
///
/// [child] is drawn inside the [NextRankProgressLayout.ring] and
/// [NextRankProgressLayout.arc] treatments (the belt badge); the bars
/// take no child. The ring takes its box FROM the child, so the stroke
/// hugs the badge at whatever size the badge was given.
class NextRankProgress extends StatelessWidget {
  const NextRankProgress({
    super.key,
    required this.progress,
    this.layout = NextRankProgressLayout.ring,
    this.child,
  });

  final double progress;
  final NextRankProgressLayout layout;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      NextRankProgressLayout.ring => _ring(),
      NextRankProgressLayout.arc => _arc(),
      NextRankProgressLayout.bar => _bar(
        height: _kBarHeight,
        radius: BorderRadius.circular(DesignConstants.radiusCircle),
      ),
      NextRankProgressLayout.rail => _bar(
        height: _kRailHeight,
        radius: BorderRadius.zero,
      ),
    };
  }

  Widget _ring() {
    return Stack(
      children: [
        ?child,
        Positioned.fill(
          child: CustomPaint(
            painter: RankArcPainter(
              progress: progress,
              color: DesignConstants.text,
              strokeWidth: DesignConstants.buttonBorderSize,
            ),
          ),
        ),
      ],
    );
  }

  Widget _arc() {
    return SizedBox(
      width: _kArcSize,
      height: _kArcSize,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: RankArcPainter(
                progress: progress,
                color: DesignConstants.text,
                trackColor: DesignConstants.text3rd,
                strokeWidth: _kArcStroke,
              ),
            ),
          ),
          if (child != null) Center(child: child),
        ],
      ),
    );
  }

  Widget _bar({required double height, required BorderRadius radius}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filled = constraints.maxWidth.isFinite
            ? constraints.maxWidth * progress.clamp(0.0, 1.0)
            : 0.0;
        return Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DesignConstants.text3rd,
                  borderRadius: radius,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: filled,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DesignConstants.text,
                  borderRadius: radius,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
