// Ports ../../../../ThemeFlutter/test/theme_asset_warmer_test.dart's
// `computeTargets` group. Its second group — the flutter_svg cache evict-key
// round-trip — has no counterpart: the browser's HTTP cache is not addressable
// from JavaScript, so this runtime warms and never evicts (see ../theme/
// assetWarmer.ts for the full reasoning).

import { describe, expect, it } from 'vitest';

import type { ThemeConfig } from '../models/themeConfig';
import { parseThemeConfig } from '../models/themeConfig';
import { computeAssetTargets } from '../theme/assetWarmer';

/** Stand-in for the client's `resolveImageUrl`. */
const resolve = (raw: string): string => (raw.startsWith('http') ? raw : `http://host/${raw}`);

function config(
  images: Record<string, string>,
  icons: Record<string, string> = {},
): ThemeConfig {
  return parseThemeConfig({ images, icons });
}

describe('computeAssetTargets', () => {
  it('yields empty sets for a null config', () => {
    const targets = computeAssetTargets(null, resolve);
    expect(targets.images).toEqual([]);
    expect(targets.icons).toEqual([]);
  });

  it('resolves relative URLs and keeps absolute ones', () => {
    const targets = computeAssetTargets(
      config({ bg: 'images/bg.png', logo: 'https://cdn/logo.png' }, { nav: 'icons/nav.svg' }),
      resolve,
    );
    expect([...targets.images].sort()).toEqual([
      'http://host/images/bg.png',
      'https://cdn/logo.png',
    ]);
    expect(targets.icons).toEqual(['http://host/icons/nav.svg']);
  });

  it('dedupes URLs that resolve to the same target', () => {
    const targets = computeAssetTargets(
      config({ a: 'images/x.png', b: 'images/x.png' }),
      resolve,
    );
    expect(targets.images).toEqual(['http://host/images/x.png']);
  });

  it('drops empty slot URLs', () => {
    // An empty slot is already dropped by the wire parser, so this holds at
    // both layers — which is what keeps a mid-`expand` run from warming "".
    const targets = computeAssetTargets(
      config({ a: 'images/x.png', b: '' }, { i: '', j: 'icons/j.svg' }),
      resolve,
    );
    expect(targets.images).toEqual(['http://host/images/x.png']);
    expect(targets.icons).toEqual(['http://host/icons/j.svg']);
  });
});
