import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Enforced ratio + max width for the upload preview, so it reads as a
/// sensible image field rather than a full-bleed banner.
const double _kUploadAspect = 16 / 9;
const double _kUploadMaxWidth = 360;

/// Labeled image upload box. Shows an upload prompt when empty, or a preview
/// when set. A network [imageUrl] (the selected gym's class image) is preferred,
/// else a bundled [imageAsset]. The prototype tap is a no-op.
class ImageUploadField extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final String? imageAsset;
  final VoidCallback? onTap;

  const ImageUploadField({
    super.key,
    required this.label,
    this.imageUrl,
    this.imageAsset,
    this.onTap,
  });

  bool get _hasImage =>
      (imageUrl != null && imageUrl!.isNotEmpty) || imageAsset != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: DesignConstants.h2),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kUploadMaxWidth),
            child: AspectRatio(
              aspectRatio: _kUploadAspect,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: DesignConstants.card,
                    borderRadius:
                        BorderRadius.circular(DesignConstants.radiusBig),
                    border: Border.all(
                      color: DesignConstants.text3rd,
                      width: DesignConstants.buttonBorder,
                    ),
                  ),
                  child: _hasImage
                      ? _Preview(imageUrl: imageUrl, asset: imageAsset)
                      : const _UploadPrompt(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadPrompt extends StatelessWidget {
  const _UploadPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.add_photo_alternate_sharp,
            size: DesignConstants.iconSizeBig,
            color: DesignConstants.text3rd,
            weight: DesignConstants.iconWeight,
          ),
          Text(
            'Upload image',
            style: DesignConstants.p.copyWith(color: DesignConstants.text3rd),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final String? imageUrl;
  final String? asset;
  const _Preview({this.imageUrl, this.asset});

  // Network (the gym's class image) wins; on a load error or no URL, fall back
  // to the bundled asset, then a plain card-colored box. Mirrors
  // `ClassCard._CardImage`.
  Widget _image() {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    if (asset != null) return Image.asset(asset!, fit: BoxFit.cover);
    return ColoredBox(color: DesignConstants.card);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _image(),
        Positioned(
          right: DesignConstants.spacingMedium,
          bottom: DesignConstants.spacingMedium,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignConstants.spacingMedium,
              vertical: DesignConstants.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: DesignConstants.popup,
              borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
            ),
            child: Text(
              'Change',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
