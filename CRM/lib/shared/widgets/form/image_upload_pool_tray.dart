import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';

/// Horizontally-scrollable strip of default-image chips plus a trailing
/// upload tile, rendered below the preview in [ImageUploadPickerField] when
/// its `poolImages` list is non-empty. Composed by the picker; picking a chip
/// is synchronous (no upload) and fires [onPick], while the trailing tile
/// opens the same file picker as the main preview via [onUpload].
class ImageUploadPoolTray extends StatelessWidget {
  final List<String> poolImages;
  final double aspectRatio;
  final String? selectedUrl;
  final bool disabled;
  final ValueChanged<String> onPick;
  final VoidCallback onUpload;

  const ImageUploadPoolTray({
    super.key,
    required this.poolImages,
    required this.aspectRatio,
    required this.selectedUrl,
    required this.disabled,
    required this.onPick,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return HorizontalScroller(
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final url in poolImages)
          _PoolChip(
            imageUrl: url,
            aspectRatio: aspectRatio,
            selected: url == selectedUrl,
            onTap: disabled ? null : () => onPick(url),
          ),
        _UploadTile(
          aspectRatio: aspectRatio,
          onTap: disabled ? null : onUpload,
        ),
      ],
    );
  }
}

/// A single tappable pool image. Selected: a sapphire ring + a check badge;
/// unselected: the same neutral hairline the preview box uses.
class _PoolChip extends StatelessWidget {
  final String imageUrl;
  final double aspectRatio;
  final bool selected;
  final VoidCallback? onTap;

  const _PoolChip({
    required this.imageUrl,
    required this.aspectRatio,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        height: DesignConstants.poolChipHeight,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: DesignConstants.card,
                    borderRadius:
                        BorderRadius.circular(DesignConstants.radiusSmall),
                    border: Border.all(
                      color: selected
                          ? DesignConstants.primaryColor
                          : DesignConstants.text3rd,
                      width: DesignConstants.buttonBorder,
                    ),
                  ),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: DesignConstants.card),
                  ),
                ),
                if (selected) const _CheckBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small accent circle with an onAccent check, pinned to a selected chip's
/// top-right corner. A static ring — no scale animation (reduced motion).
class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: DesignConstants.spacingTiny,
      right: DesignConstants.spacingTiny,
      child: Container(
        width: DesignConstants.iconSizeLarge,
        height: DesignConstants.iconSizeLarge,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignConstants.primaryColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Symbols.check_sharp,
          size: DesignConstants.iconSizeTiny,
          color: DesignConstants.onAccent,
          weight: DesignConstants.iconWeight,
        ),
      ),
    );
  }
}

/// Trailing tile in the pool tray that opens the file picker — the same
/// upload path as the main preview box.
class _UploadTile extends StatelessWidget {
  final double aspectRatio;
  final VoidCallback? onTap;

  const _UploadTile({required this.aspectRatio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignConstants.poolChipHeight,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignConstants.card,
              borderRadius:
                  BorderRadius.circular(DesignConstants.radiusSmall),
              border: Border.all(
                color: DesignConstants.text3rd,
                width: DesignConstants.buttonBorder,
              ),
            ),
            child: Center(
              child: Icon(
                Symbols.add_photo_alternate_sharp,
                size: DesignConstants.iconSizeMedium,
                color: DesignConstants.text3rd,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
