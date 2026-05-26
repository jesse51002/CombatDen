import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:mobile_app/core/design_constants.dart';
import 'package:customization_engine/data/models/customization_style.dart';

/// A tappable style preset: its celebration image as a 3:2 hero with
/// the design name below. The active style shows a check badge. Tapping
/// switches the live theme (handled by the caller).
class StyleCard extends StatelessWidget {
  const StyleCard({
    super.key,
    required this.style,
    required this.isActive,
    required this.onTap,
  });

  final CustomizationStyle style;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
            _StyleImageHero(
              imageUrl: style.celebrationImageUrl,
              isActive: isActive,
            ),
            Padding(
              padding: EdgeInsets.all(DesignConstants.paddingSmall),
              child: Text(
                style.displayName,
                style: DesignConstants.h2,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3:2 celebration image with an "active" check badge pinned top-right.
class _StyleImageHero extends StatelessWidget {
  const _StyleImageHero({required this.imageUrl, required this.isActive});

  final String imageUrl;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => const _ImagePlaceholder(),
            errorWidget: (context, url, error) => const _ImagePlaceholder(),
          ),
          if (isActive)
            Positioned(
              top: DesignConstants.spacingMedium,
              right: DesignConstants.spacingMedium,
              child: const _ActiveBadge(),
            ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.popup,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          weight: DesignConstants.iconWeight,
          color: DesignConstants.text3rd,
          size: DesignConstants.iconSize2xl,
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(DesignConstants.spacingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.primaryColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Symbols.check_sharp,
        weight: DesignConstants.iconWeight,
        color: DesignConstants.primaryButtonText,
        size: DesignConstants.iconSizeLg,
      ),
    );
  }
}
