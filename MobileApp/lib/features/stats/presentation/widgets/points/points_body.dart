import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';

/// Hero illustration + "+N points" caption for the Points celebration card.
class PointsBody extends StatelessWidget {
  const PointsBody({super.key, required this.stats});

  final MockPointsStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        Image.asset(
          stats.heroAsset,
          width: 238,
          height: 238,
          fit: BoxFit.contain,
        ),
        Text(
          stats.amountLabel,
          textAlign: TextAlign.center,
          style: DesignConstants.big2,
        ),
      ],
    );
  }
}
