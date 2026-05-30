import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:theme_flutter/customization_service.dart';
import 'package:theme_flutter/data/models/customization.dart';

/// Warms the caches for the active theme's images + icons so they show
/// instantly when first rendered, and — crucially — evicts the *previous*
/// theme's warmed assets on every switch so the caches don't grow without
/// bound across a long session of flipping themes.
///
/// App-agnostic, web-safe, never throws: it is a best-effort cache primer.
/// Per-URL failures (offline, 404, corrupt) are swallowed — the resolvers
/// (`ThemeImage` / `ThemeIcon`) already fall back gracefully, and the cache
/// fills opportunistically next time.
///
/// **Mode-aware images.** `ThemeImage` picks its provider by
/// `service.livePreview`, so the warmer must target the matching cache:
///   * `livePreview` (admin live preview) → plain `NetworkImage`, so warm/evict
///     Flutter's RAM [ImageCache] (`PaintingBinding.instance.imageCache`).
///   * production (member app) → `CachedNetworkImageProvider`, so warm/evict
///     the `flutter_cache_manager` disk cache ([DefaultCacheManager], the same
///     store `cached_network_image` reads from).
///
/// **Mode-independent icons.** `ThemeIcon` always renders via
/// `SvgPicture.network`, which caches into `flutter_svg`'s global [svg.cache]
/// regardless of mode — so icons take one path either way.
///
/// Owned by [ThemeService], which calls [onConfigChanged] after every
/// `initialize` / `selectDesign`.
class ThemeAssetWarmer {
  /// Absolute URLs warmed for the currently-loaded theme — the set to evict
  /// on the next switch. Kept here (not on the service) so the service stays
  /// free of cache bookkeeping.
  Set<String> _warmedImageUrls = const {};
  Set<String> _warmedIconUrls = const {};

  /// Evicts the previously-warmed theme's assets and warms the freshly-loaded
  /// one's. Fire-and-forget. The bookkeeping (steps 1–3) is **synchronous** so
  /// two rapid switches can't interleave: the second call sees the first call's
  /// new set as its `previous`. Only the I/O (step 4) is detached.
  void onConfigChanged(ThemeService service) {
    // 1. Resolve the new theme's targets.
    final (nextImages, nextIcons) =
        computeTargets(service.current, service.resolveImageUrl);

    // 2. Same design re-selected (or nothing changed): nothing to do. Avoids a
    //    pointless disk removeFile→downloadFile churn for the member app.
    if (_setEquals(nextImages, _warmedImageUrls) &&
        _setEquals(nextIcons, _warmedIconUrls)) {
      return;
    }

    // 3. Snapshot the previous set, then claim the new one — synchronously,
    //    before any await, so the next call can't race this.
    final prevImages = _warmedImageUrls;
    final prevIcons = _warmedIconUrls;
    _warmedImageUrls = nextImages;
    _warmedIconUrls = nextIcons;

    // 4. Detached I/O: drop the old theme, then prime the new one.
    final livePreview = service.livePreview;
    for (final url in prevImages) {
      _evictImage(url, livePreview: livePreview);
    }
    for (final url in prevIcons) {
      _evictIcon(url);
    }
    for (final url in nextImages) {
      _warmImage(url, livePreview: livePreview);
    }
    for (final url in nextIcons) {
      _warmIcon(url);
    }
  }

  /// The resolved, deduped, non-empty image + icon URLs for [config]. Pure —
  /// no I/O, no state — so it can be unit-tested directly.
  static (Set<String> images, Set<String> icons) computeTargets(
    ThemeConfig? config,
    String Function(String raw) resolve,
  ) {
    if (config == null) return (const {}, const {});
    return (_resolveAll(config.images.values, resolve),
        _resolveAll(config.icons.values, resolve));
  }

  static Set<String> _resolveAll(
    Iterable<String> raws,
    String Function(String raw) resolve,
  ) {
    final urls = <String>{};
    for (final raw in raws) {
      if (raw.isEmpty) continue;
      urls.add(resolve(raw));
    }
    return urls;
  }

  // --- Image cache (mode-aware) ------------------------------------------

  void _warmImage(String url, {required bool livePreview}) {
    try {
      if (livePreview) {
        // Prime the RAM ImageCache without a BuildContext. This is what
        // precacheImage does internally (minus the context it needs):
        // resolving against an empty configuration is safe because
        // NetworkImage's cache key is configuration-independent, so the
        // render-time resolve is a hit. The listener removes itself on both
        // success and error so nothing leaks.
        final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (ImageInfo image, bool _) => stream.removeListener(listener),
          onError: (Object _, StackTrace? _) =>
              stream.removeListener(listener),
        );
        stream.addListener(listener);
      } else {
        // Warm the disk cache cached_network_image reads from.
        unawaited(_swallow(DefaultCacheManager().downloadFile(url)));
      }
    } catch (e) {
      debugPrint('[CUSTOMIZATION] image warm skipped ($url): $e');
    }
  }

  void _evictImage(String url, {required bool livePreview}) {
    try {
      if (livePreview) {
        // Evicts the inner NetworkImage entry. The FallbackImageProvider
        // wrapper entry is keyed on (NetworkImage, fallback) and the engine
        // can't reconstruct the caller's bundled fallback, so that thin
        // wrapper is left to normal LRU — see ThemeImage. Clearing the whole
        // cache would nuke unrelated images and the new theme we just warmed.
        PaintingBinding.instance.imageCache.evict(NetworkImage(url));
      } else {
        unawaited(_swallow(DefaultCacheManager().removeFile(url)));
      }
    } catch (e) {
      debugPrint('[CUSTOMIZATION] image evict skipped ($url): $e');
    }
  }

  // --- Icon cache (flutter_svg, mode-independent) ------------------------

  void _warmIcon(String url) {
    try {
      // Populates svg.cache under the same key the render path uses.
      unawaited(_swallow(SvgNetworkLoader(url).loadBytes(null)));
    } catch (e) {
      debugPrint('[CUSTOMIZATION] icon warm skipped ($url): $e');
    }
  }

  void _evictIcon(String url) {
    try {
      // The evict key assumes NO DefaultSvgTheme ancestor: ThemeIcon passes no
      // `theme:`, so render-time getTheme(context) resolves const SvgTheme(),
      // matching cacheKey(null) here. ThemeIcon tints via colorFilter (not
      // colorMapper), so cached bytes are tint-independent — one entry per URL.
      // If a consumer ever installs DefaultSvgTheme, this key would diverge.
      svg.cache.evict(SvgNetworkLoader(url).cacheKey(null));
    } catch (e) {
      debugPrint('[CUSTOMIZATION] icon evict skipped ($url): $e');
    }
  }

  // --- Helpers ------------------------------------------------------------

  /// Swallows a future's error so a failed warm/evict never escapes as an
  /// unhandled async error. (The engine never throws on a bad override asset.)
  static Future<void> _swallow(Future<Object?> future) =>
      future.then((_) {}, onError: (Object _, StackTrace _) {});

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
