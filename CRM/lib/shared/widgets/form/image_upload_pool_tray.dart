import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/horizontal_scroller.dart';

/// Horizontally-scrollable strip of default-image chips plus a trailing
/// upload tile, rendered below the preview in [ImageUploadPickerField] when
/// its `poolImages` list is non-empty. Composed by the picker; picking a chip
/// is synchronous (no upload) and fires [onPick], while the trailing tile
/// opens the same file picker as the main preview via [onUpload].
///
/// A chip whose image fails to load (the preset CDN asset isn't uploaded yet,
/// or any future CDN failure) collapses out of the strip rather than rendering
/// as a dead gray tile — see [_ImageUploadPoolTrayState._failed]. The upload
/// tile always stays; if every pool image fails, only it remains.
class ImageUploadPoolTray extends StatefulWidget {
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
  State<ImageUploadPoolTray> createState() => _ImageUploadPoolTrayState();
}

class _ImageUploadPoolTrayState extends State<ImageUploadPoolTray> {
  // URLs whose Image.network failed to load. A failed URL is filtered out of
  // the rendered strip so a broken chip never lingers as a dead gray tile.
  // The chip reports its failure from an errorBuilder (which fires during
  // build) via a post-frame callback; this set is the "report once" guard —
  // the first report adds the URL and rebuilds, dropping the chip, so the
  // errorBuilder stops firing for it. A failed pool URL is dropped even when
  // it is the caller's current selection; the caller keeps its stored value.
  final Set<String> _failed = <String>{};

  void _markFailed(String url) {
    if (!mounted || _failed.contains(url)) return;
    setState(() => _failed.add(url));
  }

  @override
  Widget build(BuildContext context) {
    return HorizontalScroller(
      spacing: DesignConstants.spacingMedium,
      children: [
        for (final url in widget.poolImages)
          if (!_failed.contains(url))
            _PoolChip(
              key: ValueKey<String>(url),
              imageUrl: url,
              aspectRatio: widget.aspectRatio,
              selected: url == widget.selectedUrl,
              onTap: widget.disabled ? null : () => widget.onPick(url),
              onError: () => _markFailed(url),
            ),
        _UploadTile(
          aspectRatio: widget.aspectRatio,
          onTap: widget.disabled ? null : widget.onUpload,
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

  /// Fired when [imageUrl] fails to load so the tray can drop this chip. The
  /// errorBuilder runs during build, so the report is deferred to a post-frame
  /// callback — never a direct `setState`.
  final VoidCallback onError;

  const _PoolChip({
    super.key,
    required this.imageUrl,
    required this.aspectRatio,
    required this.selected,
    required this.onTap,
    required this.onError,
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
                    errorBuilder: (_, _, _) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => onError());
                      return ColoredBox(color: DesignConstants.card);
                    },
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
