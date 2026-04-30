import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_tile.dart';

/// Three equally-sized [WinsTile]s in a row.
class WinsTileRow extends StatelessWidget {
  const WinsTileRow({super.key, required this.tiles});

  final List<MockWinTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final tile in tiles)
          Expanded(child: WinsTile(tile: tile)),
      ],
    );
  }
}
