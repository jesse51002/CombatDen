import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';

/// Bordered info-tile shown in the Wins grid: icon + value + caption.
class WinsTile extends StatelessWidget {
  const WinsTile({super.key, required this.tile});

  final MockWinTile tile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        border: Border.all(
          color: DesignConstants.text,
          width: DesignConstants.buttonBorder,
        ),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            _iconFor(tile.iconName),
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text,
            size: DesignConstants.iconSizeXl,
          ),
          Text(
            tile.value,
            textAlign: TextAlign.center,
            style: DesignConstants.h3,
          ),
          Text(
            tile.label,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String iconName) {
    switch (iconName) {
      case 'star':
        return Symbols.star_sharp;
      case 'award':
        return Symbols.workspace_premium_sharp;
      case 'gift':
        return Symbols.redeem_sharp;
      default:
        return Symbols.help_sharp;
    }
  }
}
