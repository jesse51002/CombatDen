import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/wins/wins_tile_row.dart';

/// Hero illustration + "Today's wins" header + the three info tiles.
class WinsBody extends StatelessWidget {
  const WinsBody({super.key, required this.stats});

  final MockWinsStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        Image.asset(
          stats.heroAsset,
          width: 230,
          height: 230,
          fit: BoxFit.contain,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: DesignConstants.spacingMedium,
          children: [
            Text(
              stats.title,
              textAlign: TextAlign.center,
              style: DesignConstants.big2,
            ),
            Text(
              stats.subtitle,
              textAlign: TextAlign.center,
              style: DesignConstants.pBig.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          ],
        ),
        WinsTileRow(tiles: stats.tiles),
      ],
    );
  }
}
