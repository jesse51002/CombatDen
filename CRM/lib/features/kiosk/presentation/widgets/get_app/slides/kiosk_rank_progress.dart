import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/measured_max_width.dart';

/// How full the showcase's rank bar sits: obviously partial, past halfway. A
/// nearly-empty bar makes the feature look like work, a nearly full one makes
/// it look finished, and this panel is selling the climb.
const double _kShowcaseFill = 0.6;

/// Denominator when the featured rung carries no usable threshold (a gym that
/// left `classes_to_next_major` at 0 or 1).
const int _kFallbackTarget = 20;

/// The "Track rank" slide's progress bar — "{done} / {target} classes to
/// {next belt}" over a sapphire rail.
///
/// The numerator is fabricated, deliberately (see `KioskRankSlide`). Real are
/// [target] — the featured rung's own `classes_to_next_major` — and
/// [nextRankName], so a gym owner watching the pitch sees their own
/// requirement and their own belts. No word here is second person about
/// anybody's standing; the line is a label on a diagram.
class KioskRankProgress extends StatelessWidget {
  /// The featured rung's real `classes_to_next_major`.
  final int target;

  /// The next belt on the gym's ladder, when the featured rung has one.
  final String? nextRankName;

  const KioskRankProgress({
    super.key,
    required this.target,
    this.nextRankName,
  });

  @override
  Widget build(BuildContext context) {
    final total = target >= 2 ? target : _kFallbackTarget;
    var done = (total * _kShowcaseFill).round();
    if (done < 1) done = 1;
    if (done > total - 1) done = total - 1;
    return MeasuredMaxWidth(
      maxWidth: DesignConstants.kioskGlanceMeasure,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          _Line(done: done, total: total, nextRankName: nextRankName),
          _Rail(fraction: done / total),
        ],
      ),
    );
  }
}

/// "15 / 25 classes to Brown" — the count in the accent so the eye ties it to
/// the rail below.
class _Line extends StatelessWidget {
  final int done;
  final int total;
  final String? nextRankName;

  const _Line({
    required this.done,
    required this.total,
    required this.nextRankName,
  });

  @override
  Widget build(BuildContext context) {
    final next = nextRankName;
    // A ladder whose featured rung is also its last has no belt to name.
    final tail = next == null ? ' classes' : ' classes to $next';
    return Text.rich(
      TextSpan(
        style: DesignConstants.kioskLabel.copyWith(
          fontWeight: FontWeight.w400,
          color: DesignConstants.text2nd,
        ),
        children: [
          TextSpan(
            text: '$done / $total',
            style: DesignConstants.kioskLabel.copyWith(
              fontWeight: FontWeight.w700,
              color: DesignConstants.primaryColor,
            ),
          ),
          TextSpan(text: tail),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// The rail itself: the admin `RankProgressBar`'s anatomy (a clipped
/// determinate bar on a hairline track), one step thicker because the kiosk is
/// read from ~2m.
class _Rail extends StatelessWidget {
  final double fraction;

  const _Rail({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: DesignConstants.kioskProgressBarThickness,
        color: DesignConstants.primaryColor,
        backgroundColor: DesignConstants.line,
      ),
    );
  }
}
