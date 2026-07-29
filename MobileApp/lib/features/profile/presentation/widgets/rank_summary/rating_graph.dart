import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/features/profile/presentation/widgets/rank_summary/rating_graph_painter.dart';
import 'package:mobile_app/shared/widgets/text/threshold_label.dart';

const List<double> _kThresholdTopOffsets = [12, 80, 140];

/// The shipped plot box: 393 wide by 196.5 tall. Every other size is
/// that ratio re-proportioned, and the threshold offsets above scale
/// with it so an annotation never falls outside a shorter plot.
const double _kNominalWidth = 393;
const double _kNominalHeight = 196.5;
const double _kShortHeight = 110;
const double _kTallHeight = 248;

/// How much room the plot gets.
enum RatingGraphSize {
  /// A strip — the collapsible seam in `splitRank`.
  sm,

  /// The shipped plot.
  md,

  /// A tall band for a graph that is the screen's main event.
  lg,
}

/// Rating-over-time line graph with rank threshold annotations on the
/// right edge.
class RatingGraph extends StatelessWidget {
  const RatingGraph({
    super.key,
    this.size = RatingGraphSize.md,
    this.bleed = false,
    this.card = false,
  });

  final RatingGraphSize size;

  /// Runs the plot to the screen edges instead of inside the standard
  /// gutter.
  final bool bleed;

  /// Seats the plot on a raised surface.
  final bool card;

  double get _height => switch (size) {
    RatingGraphSize.sm => _kShortHeight,
    RatingGraphSize.md => _kNominalHeight,
    RatingGraphSize.lg => _kTallHeight,
  };

  @override
  Widget build(BuildContext context) {
    final plot = AspectRatio(
      aspectRatio: _kNominalWidth / _height,
      child: _Plot(thresholdScale: _height / _kNominalHeight),
    );
    if (bleed) return plot;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: card ? _Surface(child: plot) : plot,
    );
  }
}

/// The raised surface the `card` treatment seats the plot on.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: child,
    );
  }
}

class _Plot extends StatelessWidget {
  const _Plot({required this.thresholdScale});

  final double thresholdScale;

  @override
  Widget build(BuildContext context) {
    final thresholds = ratingGraphThresholds;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: RatingGraphPainter(
              series: mockRatingGraphSeries,
              color: DesignConstants.text,
            ),
          ),
        ),
        for (var i = 0; i < thresholds.length; i++)
          Positioned(
            right: 0,
            top: _kThresholdTopOffsets[i] * thresholdScale,
            child: ThresholdLabel(label: thresholds[i]),
          ),
      ],
    );
  }
}
