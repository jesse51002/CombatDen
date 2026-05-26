import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'package:customization_engine/customization_service.dart';
import 'package:customization_engine/service_locator.dart';

/// App-agnostic image resolver. Mirrors `ThemeColor.color` /
/// `ThemeText.value`: looks up a slot id in the loaded customization
/// and returns a disk-cached network [ImageProvider] for it, falling
/// back to the caller's bundled [fallback] when there is no
/// customization (DI not set up, nothing loaded, slot absent, or
/// empty URL). Never throws.
///
/// The engine deliberately does NOT own a fallback: white-label
/// tenants keep their default assets bundled in their own build, so
/// the CustomizationService is a pure live override. The caller
/// passes its bundled asset as [fallback]:
/// `Image(image: ThemeImage.image(slot, fallback: ApiImage.asset(...)))`.
///
/// Contrast with `ApiImage`, which is for real business-data
/// images (class photos, rank/video/reward art) — those never go
/// through here.
class ThemeImage {
  // Private constructor to prevent instantiation.
  ThemeImage._();

  /// The customization override [ImageProvider] for [slot], or
  /// [fallback] when no customization applies to it.
  static ImageProvider image(String slot, {required ImageProvider fallback}) {
    if (!getIt.isRegistered<CustomizationService>()) return fallback;
    final service = getIt<CustomizationService>();
    final raw = service.current?.images[slot] ?? '';
    if (raw.isEmpty) return fallback;
    return CachedNetworkImageProvider(service.resolveImageUrl(raw));
  }
}
