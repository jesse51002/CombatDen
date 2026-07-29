// Covers ../models/themeColorValue.ts + ../theme/color.ts — the port of
// ../../../../ThemeFlutter/lib/data/models/customization_color.dart.

import { describe, expect, it } from 'vitest';

import { parseColorValue } from '../models/themeColorValue';
import { alphaBlend, hslLightness, rgba, toCss, withAlpha } from '../theme/color';

describe('parseColorValue — the rgb block and ONLY the rgb block', () => {
  it('reads r/g/b, defaulting a null alpha to opaque', () => {
    expect(parseColorValue({ rgb: { r: 212, g: 12, b: 26, alpha: null } })).toEqual({
      r: 212,
      g: 12,
      b: 26,
      a: 1,
    });
  });

  it('keeps a fractional alpha', () => {
    expect(parseColorValue({ rgb: { r: 0, g: 0, b: 0, alpha: 0.126 } })?.a).toBe(0.126);
  });

  it('ignores hex and oklch entirely — the service already did the conversion', () => {
    // A payload carrying every format EXCEPT rgb resolves to null, not to the
    // hex value. Re-deriving sRGB client-side would be a second, divergent
    // implementation of the pipeline's OKLCH maths.
    expect(
      parseColorValue({
        hex: '#d40c1a',
        oklch: { l: 0.55, c: 0.22, h: 27 },
        hsl: { h: 355, s: 89, l: 43 },
      }),
    ).toBeNull();
  });

  it('returns null for every malformed shape instead of throwing', () => {
    expect(parseColorValue(null)).toBeNull();
    expect(parseColorValue('#fff')).toBeNull();
    expect(parseColorValue({})).toBeNull();
    expect(parseColorValue({ rgb: 'nope' })).toBeNull();
    expect(parseColorValue({ rgb: { r: 1, g: 2 } })).toBeNull();
    expect(parseColorValue({ rgb: { r: '1', g: 2, b: 3 } })).toBeNull();
    expect(parseColorValue({ rgb: { r: Number.NaN, g: 2, b: 3 } })).toBeNull();
  });

  it('clamps out-of-range channels rather than rejecting the colour', () => {
    expect(parseColorValue({ rgb: { r: 300, g: -20, b: 12.6, alpha: 4 } })).toEqual({
      r: 255,
      g: 0,
      b: 13,
      a: 1,
    });
  });
});

describe('colour maths', () => {
  it('stringifies to rgba(), the one notation valid at any alpha', () => {
    expect(toCss(rgba(212, 12, 26))).toBe('rgba(212, 12, 26, 1)');
    expect(toCss(rgba(212, 12, 26, 0.5))).toBe('rgba(212, 12, 26, 0.5)');
  });

  it('withAlpha keeps the channels and clamps the opacity', () => {
    expect(withAlpha(rgba(1, 2, 3), 0.25)).toEqual({ r: 1, g: 2, b: 3, a: 0.25 });
    expect(withAlpha(rgba(1, 2, 3), 9).a).toBe(1);
  });

  it('alphaBlend composites over the background', () => {
    const blended = alphaBlend(rgba(255, 255, 255, 0.5), rgba(0, 0, 0));
    expect(blended).toEqual({ r: 128, g: 128, b: 128, a: 1 });
    // Opaque foreground and fully-transparent foreground both short-circuit.
    expect(alphaBlend(rgba(1, 2, 3), rgba(9, 9, 9))).toEqual({ r: 1, g: 2, b: 3, a: 1 });
    expect(alphaBlend(rgba(1, 2, 3, 0), rgba(9, 9, 9))).toEqual({ r: 9, g: 9, b: 9, a: 1 });
  });

  it('hslLightness reports 0 for black, 1 for white, ~0.5 for a mid hue', () => {
    expect(hslLightness(rgba(0, 0, 0))).toBe(0);
    expect(hslLightness(rgba(255, 255, 255))).toBe(1);
    expect(hslLightness(rgba(212, 12, 26))).toBeCloseTo(0.439, 2);
  });
});