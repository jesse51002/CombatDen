import 'package:flutter/material.dart';
import 'package:customization_engine/showcase/celebrations/showcase_celebration_stats.dart';
import 'package:customization_engine/showcase/celebrations/wins_tile.dart';
import 'package:customization_engine/showcase/showcase_tokens.dart';
import 'package:customization_engine/theme/lottie/celebration_timings.dart';

/// Clone of MobileApp's `WinsTileRow`: three equally-sized [WinsTile]s in a
/// row, cascading in left-to-right from [baseDelay].
class WinsTileRow extends StatelessWidget {
  const WinsTileRow({
    super.key,
    required this.tiles,
    this.baseDelay = Duration.zero,
  });

  final List<ShowcaseWinTile> tiles;
  final Duration baseDelay;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: ShowcaseTokens.spacingMedium,
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
