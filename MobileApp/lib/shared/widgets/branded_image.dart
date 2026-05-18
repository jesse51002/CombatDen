import 'package:flutter/material.dart';

import 'package:mobile_app/customization/brand_image.dart';

/// Renders a CustomizationService-overridable image for [slot].
///
/// If the loaded tenant customization supplies an image for [slot]
/// it renders that (disk-cached) and, on load failure, falls back
/// to [fallback]. With no customization at all it renders
/// [fallback] directly. [fallback] is the call site's existing
/// bundled `ApiImage.*` provider — the engine never owns it, so
/// the app still works with zero backend (the white-label
/// resilience property).
///
/// Use for theme/brand slots only. Real business-data images
/// (class photos, rank/video/reward art) stay plain
/// `Image(image: ApiImage.*)` — they are not slot-overridable.
class BrandedImage extends StatelessWidget {
  const BrandedImage({
    super.key,
    required this.slot,
    required this.fallback,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
  });

  /// Customization slot id (see `CombatDenSlots`).
  final String slot;

  /// Bundled provider rendered when [slot] has no customization
  /// override, or the override fails to load.
  final ImageProvider fallback;

  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final override = BrandImage.of(slot);
    if (override == null) return _image(fallback);
    return _image(override, errorBuilder: (_, _, _) => _image(fallback));
  }

  Widget _image(
    ImageProvider provider, {
    ImageErrorWidgetBuilder? errorBuilder,
  }) {
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: errorBuilder,
    );
  }
}
