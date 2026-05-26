import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/growth/data/mock_growth.dart';
import 'package:app_management/shared/widgets/progress_arc.dart';

/// One donut tile — ring with a centered headline (e.g. "9%") and a
/// small caption underneath (e.g. "In Last 30 days"). Fills whatever
/// size its parent gives it (the ring scales to the box); wrap in an
/// `AspectRatio`/`SizedBox` to control dimensions.
class DonutStat extends StatelessWidget {
  final DonutChartData data;

  const DonutStat({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ProgressArc(
          progress: data.progress,
          progressColor: data.color,
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                data.headline,
                style: DesignConstants.big2Bold,
              ),
              Text(
                data.subLabel,
                style: DesignConstants.p.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
