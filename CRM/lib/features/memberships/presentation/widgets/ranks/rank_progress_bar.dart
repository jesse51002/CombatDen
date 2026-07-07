import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Attendance progress toward the next leaf: "X / Y classes" over a thin
/// bar, green once the member has met the threshold.
///
/// The one renderer for rank-progress — shared by the ready-to-promote
/// board ([ReadyToPromoteRow]) and the rank-detail roster so a member's
/// progress reads identically wherever it appears. When [target] is null
/// or zero the member has no further step (top of the ladder, or a
/// sub-less top belt): the bar fills and the count reads "$done classes".
class RankProgressBar extends StatelessWidget {
  /// Classes attended since the member's last rank change.
  final int done;

  /// Classes needed to reach the next leaf, or null when there is no
  /// further step.
  final int? target;

  /// True once [done] has met [target] — flips the bar to green and adds
  /// the "Eligible" marker.
  final bool eligible;

  const RankProgressBar({
    super.key,
    required this.done,
    required this.target,
    required this.eligible,
  });

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    final hasTarget = target != null && target > 0;
    final ratio = hasTarget ? (done / target).clamp(0.0, 1.0) : 1.0;
    final color =
        eligible ? DesignConstants.goodGreen : DesignConstants.primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingSmall,
      children: [
        Row(
          children: [
            Text(
              hasTarget ? '$done / $target classes' : '$done classes',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
            const Spacer(),
            if (eligible)
              Text(
                'Eligible',
                style: DesignConstants.pSmallSemibold.copyWith(
                  color: DesignConstants.goodGreen,
                ),
              ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: DesignConstants.progressBarThickness,
            color: color,
            backgroundColor: DesignConstants.text3rd.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}
