import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'package:mobile_app/customization/customization_service.dart';
import 'package:mobile_app/customization/service_locator.dart';

/// App-agnostic image resolver. Mirrors `BrandColor`: looks up a
/// slot id in the loaded customization and returns a disk-cached
/// network [ImageProvider] for it, or `null` when there is no
/// customization (DI not set up, nothing loaded, slot absent, or
/// empty URL). Never throws.
///
/// The engine deliberately does NOT own a fallback: white-label
/// tenants keep their default assets bundled in their own build,
/// so the CustomizationService is a pure live override. A `null`
/// return means "render your bundled asset". See `BrandedImage`
/// for the app-side widget that pairs this with that fallback.
///
/// Contrast with `ApiImage`, which is for real business-data
/// images (class photos, rank/video/reward art) — those never go
/// through here.
class BrandImage {
  // Private constructor to prevent instantiation.
  BrandImage._();

  /// The customization override [ImageProvider] for [slot], or
  /// `null` when no customization applies to it.
  static ImageProvider? of(String slot) {
    if (!getIt.isRegistered<CustomizationService>()) return null;
    final service = getIt<CustomizationService>();
    final raw = service.current?.images[slot] ?? '';
    if (raw.isEmpty) return null;
    return CachedNetworkImageProvider(service.resolveImageUrl(raw));
  }
}
