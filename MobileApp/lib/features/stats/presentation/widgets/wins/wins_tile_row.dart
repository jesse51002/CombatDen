import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_tile.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';

/// Three equally-sized [WinsTile]s in a row, cascading in left-to-right
/// from [baseDelay].
class WinsTileRow extends StatelessWidget {
  const WinsTileRow({
    super.key,
    required this.tiles,
    this.baseDelay = Duration.zero,
  });

  final List<MockWinTile> tiles;
  final Duration baseDelay;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (var i = 0; i < tiles.length; i++)
          Expanded(
            child: WinsTile(
              tile: tiles[i],
              delay: baseDelay + CelebrationTimings.badgeStagger * i * 2,
            ),
          ),
      ],
    );
  }
}
