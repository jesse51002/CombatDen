import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'package:customization_engine/customization_service.dart';
import 'package:customization_engine/service_locator.dart';
import 'package:customization_engine/theme/fallback_image_provider.dart';

/// App-agnostic image resolver. Mirrors `ThemeColor.color` /
/// `ThemeText.value`: looks up a slot id in the loaded customization
/// and returns a network [ImageProvider] for it, falling back to the
/// caller's bundled [fallback] when there is no customization (DI not
/// set up, nothing loaded, slot absent, or empty URL) AND when a present
/// slot's network bytes fail to load (404, timeout, corrupt). Never throws
/// and never renders a broken image — see [FallbackImageProvider].
///
/// Normally returns a disk-cached [CachedNetworkImageProvider]. When the
/// service is in `livePreview` mode (admin live preview) it returns a
/// plain RAM-only [NetworkImage] instead, so repeated dev reloads don't
/// pile up disk-cache files. Cache-busting is the server's job either
/// way: each asset URL carries a content-hash `?v=` token that changes
/// only when the bytes change, so an edit is picked up on the next config
/// fetch (a page reload, in the web preview).
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
    final url = service.resolveImageUrl(raw);
    final ImageProvider base = service.livePreview
        // Plain RAM-only provider — no disk cache to litter on repeated dev
        // reloads. The URL already carries the server's content-hash `?v=`
        // token, so it busts correctly whenever the asset's bytes change.
        ? NetworkImage(url)
        : CachedNetworkImageProvider(url);
    // The CustomizationService is a best-effort live override: if these
    // network bytes fail (404, timeout, corrupt) the resolver degrades to
    // the caller's bundled [fallback] — a bad override asset must never
    // surface as a thrown HttpException or a broken image box in the app.
    return FallbackImageProvider(base, fallback);
  }
}
