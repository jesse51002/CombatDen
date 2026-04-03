import 'package:flutter/material.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';

/// Status dot + time-ago text for last class attended.
///
/// Dot color is based on [AppConstants] thresholds:
/// - green: ≤ 5 days
/// - yellow: ≤ 14 days
/// - red: > 14 days
class LastClassIndicator extends StatelessWidget {
  final int? daysSinceLastClass;

  const LastClassIndicator({
    super.key,
    this.daysSinceLastClass,
  });

  @override
  Widget build(BuildContext context) {
    if (daysSinceLastClass == null) {
      return Text(
        '—',
        style: DesignConstants.h3.copyWith(
          color: DesignConstants.text,
        ),
      );
    }

    final color = _dotColor(daysSinceLastClass!);
    final text = _formatDays(daysSinceLastClass!);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: color,
            borderRadius: BorderRadius.all(Radius.circular(100))
          ),
        ),
        const SizedBox(
          width: DesignConstants.spacingMedium,
        ),
        Flexible(
          child: Text(
            text,
            style: DesignConstants.h3.copyWith(
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _dotColor(int days) {
    if (days <=
        AppConstants.lastClassThresholdRecent) {
      return DesignConstants.goodGreen;
    }
    if (days <=
        AppConstants.lastClassThresholdModerate) {
      return DesignConstants.okYellow;
    }
    return DesignConstants.badRed;
  }

  String _formatDays(int days) {
    if (days == 0) return 'Today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }
}
