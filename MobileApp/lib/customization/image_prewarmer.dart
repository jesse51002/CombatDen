import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:mobile_app/customization/customization_service.dart';

/// Warms the on-disk image cache for every loaded image slot so
/// they load instantly when first shown. App-agnostic.
///
/// Fire-and-forget: never awaited, per-URL errors swallowed.
/// Uses the same [DefaultCacheManager] that
/// `cached_network_image` reads from.
class CustomizationImagePrewarmer {
  // Private constructor to prevent instantiation
  CustomizationImagePrewarmer._();

  static void prewarm(CustomizationService service) {
    final manager = DefaultCacheManager();
    for (final url in service.imageUrlsForPrewarm()) {
      unawaited(_warm(manager, url));
    }
  }

  static Future<void> _warm(
    BaseCacheManager manager,
    String url,
  ) async {
    try {
      await manager.downloadFile(url);
    } catch (_) {
      // Offline / 404: the caller falls back gracefully and the
      // cache fills opportunistically next launch.
    }
  }
}
