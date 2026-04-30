import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/pills/timeframe_pill.dart';

/// 1W / 1M / 1Y / ALL pill row sitting under the rating graph.
class TimeframeSelector extends StatelessWidget {
  const TimeframeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingBig,
      children: const [
        TimeframePill(label: '1W', isActive: false),
        TimeframePill(label: '1M', isActive: false),
        TimeframePill(label: '1Y', isActive: false),
        TimeframePill(label: 'ALL', isActive: true),
      ],
    );
  }
}
