import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

const double _kHeroAspect = 3 / 2;

/// One tile in the themes library. Mirrors the system's canonical
/// object-card pattern (see `admin_reward_card.dart`): panel
/// background, hero on top, **centered** title + category label
/// underneath. The active state is a sapphire `Active` pill in the
/// top-right (same convention as the reward card's price pill).
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.style,
    required this.isActive,
    required this.onTap,
  });

  final ThemeStyle style;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gymType = (style.gymType ?? '').trim();
    return Material(
      color: DesignConstants.card,
      borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(imageUrl: style.celebrationImageUrl),
                Padding(
                  padding: const EdgeInsets.all(DesignConstants.paddingSmall),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: DesignConstants.spacingSmall,
                    children: [
                      SizedBox(
                        height: DesignConstants.rewardCardTitleHeight,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(
                            style.displayName,
                            style: DesignConstants.h2,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (gymType.isNotEmpty)
                        Text(
                          gymType.toUpperCase(),
                          style: DesignConstants.h3.copyWith(
                            color: DesignConstants.text2nd,
                            letterSpacing: 0.08 *
                                DesignConstants.h3.fontSize!,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (isActive)
              const Positioned(
                top: DesignConstants.spacingMedium,
                right: DesignConstants.spacingMedium,
                child: _ActivePill(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        borderRadius:
            BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingTiny,
        children: [
          Icon(
            Symbols.check_sharp,
            color: DesignConstants.backgroundColor,
            weight: DesignConstants.iconWeight,
            size: DesignConstants.iconSizeSmall,
          ),
          Text(
            'Active',
            style: DesignConstants.pSmallBold.copyWith(
              color: DesignConstants.backgroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kHeroAspect,
      child: imageUrl.isEmpty
          ? const _Placeholder()
          : Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _Placeholder(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const _Placeholder(),
            ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.backgroundColor,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeBig,
        ),
      ),
    );
  }
}
