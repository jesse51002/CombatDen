// Ports the WARM half of ../../ThemeFlutter/lib/theme/theme_asset_warmer.dart.
//
// DIVERGENCE — the eviction half is deliberately dropped. Dart evicts the
// outgoing theme's assets on every switch because it owns two real caches it
// can address: `flutter_cache_manager`'s disk store and `flutter_svg`'s
// in-memory one, both of which would otherwise grow without bound across a long
// session of flipping themes. The browser has ONE HTTP cache, it is not
// addressable from JavaScript (there is no API to purge an entry — `Cache
// Storage` is a different, service-worker-owned store this runtime never writes
// to), and it is already LRU-evicted by the browser under its own quota. So
// there is nothing to evict and nothing to leak: warming is the whole job.
//
// What remains is the part that carried the unit test on the Dart side
// (test/theme_asset_warmer_test.dart) — the pure target computation.

import type { ThemeConfig } from '../models/themeConfig';

/** The resolved, deduped, non-empty URLs to warm for one theme. */
export interface AssetTargets {
  readonly images: readonly string[];
  readonly icons: readonly string[];
}

const NO_TARGETS: AssetTargets = Object.freeze({
  images: Object.freeze([]) as readonly string[],
  icons: Object.freeze([]) as readonly string[],
});

/**
 * The resolved, deduped, non-empty image + icon URLs for `config`. Pure — no
 * I/O, no state — so it is unit-testable directly, exactly as Dart's
 * `computeTargets` is.
 */
export function computeAssetTargets(
  config: ThemeConfig | null,
  resolve: (raw: string) => string,
): AssetTargets {
  if (config === null) return NO_TARGETS;
  return {
    images: resolveAll(Object.values(config.images), resolve),
    icons: resolveAll(Object.values(config.icons), resolve),
  };
}

/**
 * Primes the browser's HTTP cache for the active theme's images and icons so
 * they paint instantly when first rendered.
 *
 * Best-effort and never throws: per-URL failures (offline, 404, corrupt) are
 * swallowed, because the resolvers already fall back gracefully and the cache
 * fills opportunistically next time. A no-op outside the browser.
 */
export function warmThemeAssets(targets: AssetTargets): void {
  if (typeof Image === 'undefined') return;
  for (const url of [...targets.images, ...targets.icons]) {
    try {
      const probe = new Image();
      // A failed warm must not surface as an unhandled error event.
      probe.onerror = null;
      probe.src = url;
    } catch {
      // Nothing to recover: this is a cache primer, not a load path.
    }
  }
}

function resolveAll(raws: readonly string[], resolve: (raw: string) => string): string[] {
  const urls = new Set<string>();
  for (const raw of raws) {
    if (raw === '') continue;
    urls.add(resolve(raw));
  }
  return [...urls];
}
