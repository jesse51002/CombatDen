import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

// Small thumbnail — the theme list is secondary to the phone, so cards are
// compact rows rather than big hero tiles.
const double _kThumbWidth = 72;
const double _kThumbHeight = 48;

/// A compact, tappable theme row: a small celebration thumbnail, the theme
/// name, and a check when active. Tapping switches the LIVE preview theme
/// via the customization engine, so the phone re-themes instantly.
class ThemeCard extends StatelessWidget {
  final ThemeStyle style;
  final bool isActive;

  const ThemeCard({super.key, required this.style, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ThemeRuntime.selectDesign(style.id),
      child: Container(
        padding: const EdgeInsets.all(DesignConstants.spacingMedium),
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
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            _Thumb(imageUrl: style.celebrationImageUrl),
            Expanded(
              child: Text(
                style.displayName,
                style: DesignConstants.h3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive)
              Icon(
                Symbols.check_circle_sharp,
                color: DesignConstants.primaryColor,
                weight: DesignConstants.iconWeight,
                size: DesignConstants.iconSizeMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: SizedBox(
        width: _kThumbWidth,
        height: _kThumbHeight,
        child: imageUrl.isEmpty
            ? const _ThumbPlaceholder()
            : Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _ThumbPlaceholder(),
              ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignConstants.backgroundColor,
      child: Center(
        child: Icon(
          Symbols.image_sharp,
          color: DesignConstants.text3rd,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeMedium,
        ),
      ),
    );
  }
}
