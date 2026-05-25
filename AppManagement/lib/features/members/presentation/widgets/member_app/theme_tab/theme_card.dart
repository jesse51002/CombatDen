import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/members/data/mock_app_themes.dart';

/// A tappable theme preset: its celebration image as a 3:2 hero with the
/// display name below. The active theme shows a check badge and an
/// orange border. Tapping switches the live theme (no-op in prototype).
class ThemeCard extends StatelessWidget {
  final AppThemeOption theme;
  final bool isActive;

  const ThemeCard({super.key, required this.theme, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => debugPrint('TODO: select theme ${theme.id}'),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          border: isActive
              ? Border.all(
                  color: DesignConstants.primaryColor,
                  width: DesignConstants.buttonBorderSize,
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ThemeHero(
              imageAsset: theme.celebrationImageAsset,
              isActive: isActive,
            ),
            Padding(
              padding: const EdgeInsets.all(DesignConstants.paddingSmall),
              child: Text(
                theme.displayName,
                style: DesignConstants.h2,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeHero extends StatelessWidget {
  final String imageAsset;
  final bool isActive;

  const _ThemeHero({required this.imageAsset, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(imageAsset, fit: BoxFit.contain),
          if (isActive)
            Positioned(
              top: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: _ActiveBadge(),
            ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignConstants.spacingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        color: DesignConstants.backgroundColor,
        weight: DesignConstants.iconWeight,
        size: 18,
      ),
    );
  }
}
