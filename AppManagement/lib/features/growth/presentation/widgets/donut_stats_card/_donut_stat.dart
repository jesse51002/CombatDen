import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/shared/widgets/progress_arc.dart';

/// One donut tile — ring with a centered headline (e.g. "9%") and a
/// small caption underneath (e.g. "In Last 30 days").
class DonutStat extends StatelessWidget {
  final DonutChartData data;

  const DonutStat({super.key, required this.data});

  static const double _size = 128.5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ProgressArc(
              progress: data.progress,
              progressColor: data.color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                data.headline,
                style: DesignConstants.big2.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                data.subLabel,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
