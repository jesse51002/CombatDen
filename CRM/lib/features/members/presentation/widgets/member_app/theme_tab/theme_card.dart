import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:theme_flutter/data/models/customization_style.dart';

// Small thumbnail — the theme list is secondary to the phone, so cards are
// compact rows rather than big hero tiles.
const double _kThumbWidth = 72;
const double _kThumbHeight = 48;

/// A compact, tappable theme row: a small celebration thumbnail, the theme
/// name, and a state marker. Tapping switches the LIVE preview theme via the
/// customization engine, so the phone re-themes instantly.
///
/// **Two separate states, never conflated.** [isSaved] is the design members
/// actually see (`gyms.theme_design_id`); [isPreviewing] is merely what the
/// phone frame is showing right now. Only "Set as app theme" moves the first
/// one, so the filled check + heavy sapphire border belong exclusively to
/// [isSaved] — a previewed-but-unsaved row gets a quieter outline eye, a soft
/// tint, and a hairline border. Three axes separate them (glyph shape, colour,
/// border weight) plus a literal sub-label, so the meaning never rests on
/// colour alone.
class ThemeCard extends StatelessWidget {
  final ThemeStyle style;

  /// This design is the gym's saved app theme — what members see.
  final bool isSaved;

  /// This design is what the preview is currently showing.
  final bool isPreviewing;

  const ThemeCard({
    super.key,
    required this.style,
    required this.isSaved,
    required this.isPreviewing,
  });

  @override
  Widget build(BuildContext context) {
    final previewOnly = isPreviewing && !isSaved;
    final radius = BorderRadius.circular(DesignConstants.radiusBig);
    return Semantics(
      button: true,
      selected: isSaved,
      child: InkWell(
        // Records the previewed design + its category globally and brands the
        // live preview with it (theme-only — decoupled from the content gym).
        onTap: () => selectedGym.selectStyle(style),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(DesignConstants.spacingMedium),
          decoration: BoxDecoration(
            color: previewOnly
                ? DesignConstants.primaryColor10
                : DesignConstants.card,
            borderRadius: radius,
            border: isSaved
                ? Border.all(
                    color: DesignConstants.primaryColor,
                    width: DesignConstants.buttonBorderSize,
                  )
                : previewOnly
                    ? Border.all(
                        color: DesignConstants.line,
                        width: DesignConstants.dividerThickness,
                      )
                    : null,
          ),
          child: Row(
            spacing: DesignConstants.spacingMedium,
            children: [
              _Thumb(imageUrl: style.celebrationImageUrl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DesignConstants.spacingTiny,
                  children: [
                    Text(
                      style.displayName,
                      style: DesignConstants.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isSaved)
                      Text(
                        isPreviewing
                            ? 'Live for members · previewing'
                            : 'Live for members',
                        style: DesignConstants.pSmallSemibold.copyWith(
                          color: DesignConstants.primaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (previewOnly)
                      Text(
                        'Previewing only',
                        style: DesignConstants.pSmall.copyWith(
                          color: DesignConstants.text2nd,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (isSaved)
                Semantics(
                  label: 'Live for members',
                  child: Icon(
                    Symbols.check_circle_sharp,
                    color: DesignConstants.primaryColor,
                    weight: DesignConstants.iconWeight,
                    size: DesignConstants.iconSizeMedium,
                  ),
                )
              else if (previewOnly)
                Semantics(
                  label: 'Currently previewing',
                  child: Icon(
                    Symbols.visibility_sharp,
                    color: DesignConstants.text2nd,
                    weight: DesignConstants.iconWeight,
                    size: DesignConstants.iconSizeSmall,
                  ),
                ),
            ],
          ),
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
