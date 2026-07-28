import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// One cell of the `statTiles` board. Fixed height so the two tiles in
/// a row read as a pair, and clipped so a hero's sparkles stay inside
/// their own cell.
const double _kTileHeight = 176;

/// A raised cell on the tile board.
class RankTile extends StatelessWidget {
  const RankTile({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kTileHeight,
      padding: EdgeInsets.all(DesignConstants.spacingMedium),
      decoration: BoxDecoration(
        color: DesignConstants.card,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: child),
    );
  }
}
