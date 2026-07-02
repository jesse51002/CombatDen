import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/form/image_url_dialog.dart';

/// Enforced ratio + max width for the preview, so it reads as a big, obvious
/// image field (16:9, matching `ClassCard`) rather than a full-bleed banner.
const double _kPreviewAspect = 16 / 9;
const double _kPreviewMaxWidth = 520;

/// Labeled image field with a large 16:9 preview and a prominent
/// "Change image" button. Tapping the preview OR the button opens the
/// paste-a-link [ImageUrlDialog]; the confirmed URL bubbles up via [onChanged]
/// (the caller owns applying it to its form state).
///
/// [imageUrl] is the current selection. When it is null/empty (a new class
/// with no image yet), [defaultImageUrl] is previewed instead with a caption,
/// so the owner sees exactly the platform default they'll get if they don't
/// choose their own.
class ImageUploadField extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final String? defaultImageUrl;
  final ValueChanged<String>? onChanged;

  const ImageUploadField({
    super.key,
    required this.label,
    this.imageUrl,
    this.defaultImageUrl,
    this.onChanged,
  });

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  String? get _previewUrl => _hasImage ? imageUrl : defaultImageUrl;

  Future<void> _openPicker(BuildContext context) async {
    final url = await ImageUrlDialog.show(
      context: context,
      initialUrl: _hasImage ? imageUrl : null,
    );
    if (url != null) onChanged?.call(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: [
        Text(label, style: DesignConstants.h2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kPreviewMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingMedium,
            children: [
              _Preview(
                imageUrl: _previewUrl,
                onTap: () => _openPicker(context),
              ),
              if (!_hasImage)
                Text(
                  'Default image — choose your own',
                  style: DesignConstants.pSmall
                      .copyWith(color: DesignConstants.text2nd),
                ),
              AppPrimaryButton(
                text: 'Change image',
                onPressed: () => _openPicker(context),
                icon: Icon(
                  Symbols.add_photo_alternate_sharp,
                  size: DesignConstants.iconSizeMedium,
                  color: DesignConstants.onAccent,
                  weight: DesignConstants.iconWeight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The large tappable 16:9 preview. A network [imageUrl] is shown; a broken
/// URL or none falls back to a muted placeholder. Mirrors `ClassCard`'s image.
class _Preview extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onTap;

  const _Preview({required this.imageUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _kPreviewAspect,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: DesignConstants.card,
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
            border: Border.all(
              color: DesignConstants.text3rd,
              width: DesignConstants.buttonBorder,
            ),
          ),
          child: (imageUrl != null && imageUrl!.isNotEmpty)
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _Placeholder(),
                )
              : const _Placeholder(),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Symbols.image_sharp,
        size: DesignConstants.iconSizeBig,
        color: DesignConstants.text3rd,
        weight: DesignConstants.iconWeight,
      ),
    );
  }
}
