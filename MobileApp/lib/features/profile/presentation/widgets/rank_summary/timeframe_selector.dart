import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/rank_progress_selectors.dart';
import 'package:mobile_app/shared/widgets/pills/timeframe_pill.dart';

/// 1W / 1M / 1Y / ALL pill row under the rank graph. Selecting a pill windows
/// the plotted series client-side (there is no server-side windowing).
class TimeframeSelector extends StatelessWidget {
  const TimeframeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final RankTimeframe selected;
  final ValueChanged<RankTimeframe> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: [
        for (final tf in RankTimeframe.values)
          TimeframePill(
            label: tf.label,
            isActive: tf == selected,
            onTap: () => onChanged(tf),
          ),
      ],
    );
  }
}
