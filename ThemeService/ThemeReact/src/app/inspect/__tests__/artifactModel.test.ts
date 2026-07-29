// The inspector's reading of a theme is pure, so it is pinned here rather than
// through the DOM. Three things are worth the test: the hex the page prints
// beside every swatch, the ink it writes on a generated colour, and the fact
// that an ABSENT slot survives as a hole in the list instead of shortening it.

import { parseThemeConfig, rgba } from 'theme-react';
import { describe, expect, it } from 'vitest';

import {
  buildInspection,
  contrastRatio,
  DERIVATION_ORDER,
  groupPalette,
  hexOf,
  over,
  readableInk,
  relativeLuminance,
  spectrumBands,
} from '../artifactModel';

/** A `ColorValue` as the wire ships it — only the `rgb` block is read. */
function wireColor(r: number, g: number, b: number, alpha: number | null = null) {
  return { rgb: { r, g, b, alpha } };
}

function wireTheme() {
  return {
    app: 'combatden',
    display_name: 'CombatDen',
    design_name: 'Apex MMA',
    category: 'Fighting',
    images: { logo_primary: 'https://cdn/logo.png' },
    image_set: {
      images: { logo_primary: { url: 'https://cdn/logo.png', complexity: 'high' } },
    },
    fonts: { display: 'Space Grotesk', body: 'Roboto Flex' },
    font_set: {
      fonts: {
        display: {
          family: 'Space Grotesk',
          category: 'sans-serif',
          display_name: 'Athletic Modern',
          description: 'A confident geometric sans with sharp proportions.',
        },
        // A face the run produced without prose — the specimen still sets it.
        body: { family: 'Roboto Flex', category: 'sans-serif' },
      },
    },
    icons: { nav_home: 'https://cdn/home.svg' },
    color_set: {
      mode: 'dark',
      colors: {
        primary: {
          color: wireColor(212, 12, 26),
          display_name: 'Red Corner',
          description: 'A bold, saturated competition red.',
          derivations: {
            second: wireColor(212, 12, 26, 0.75),
            third: wireColor(212, 12, 26, 0.5),
            card: wireColor(212, 12, 26, 0.126),
            popup: wireColor(36, 7, 7),
            dark: wireColor(5, 0, 0),
            light: wireColor(255, 166, 156),
            regular_text: wireColor(220, 231, 240),
          },
        },
        background: {
          color: wireColor(10, 10, 12),
          display_name: 'Arena Black',
          description: 'A deep near-black.',
          derivations: { light: wireColor(240, 240, 244) },
        },
      },
      palette: {
        primary: wireColor(212, 12, 26),
        primary_second: wireColor(212, 12, 26, 0.75),
        background: wireColor(10, 10, 12),
        card: wireColor(30, 30, 36),
        divider: wireColor(60, 60, 66),
        unexpected_future_token: wireColor(1, 2, 3),
      },
    },
    text_set: { texts: { reserve_cta: { value: 'Lock it in' } } },
  };
}

const inspection = buildInspection(parseThemeConfig(wireTheme()));

describe('hexOf', () => {
  it('prints six digits for an opaque colour', () => {
    expect(hexOf(rgba(212, 12, 26, 1))).toBe('#d40c1a');
  });

  it('appends the alpha byte, matching the pipeline own 8-digit hex', () => {
    // ThemeService writes `#d40c1abf` for this exact colour at 0.75.
    expect(hexOf(rgba(212, 12, 26, 0.75))).toBe('#d40c1abf');
  });

  it('pads single-digit channels', () => {
    expect(hexOf(rgba(5, 0, 0, 1))).toBe('#050000');
  });
});

describe('readableInk', () => {
  it('writes light ink on a near-black generated ground', () => {
    expect(readableInk(rgba(10, 10, 12, 1)).r).toBe(255);
  });

  it('writes dark ink on a pale generated ground', () => {
    expect(readableInk(rgba(226, 221, 217, 1)).r).toBe(22);
  });

  it('writes dark ink on saturated yellow, where HSL lightness would not', () => {
    // hsl(50 100% 50%) is "mid" by lightness but bright by luminance; picking
    // white here would ship a 1.9:1 caption.
    const yellow = rgba(255, 212, 0, 1);
    const ink = readableInk(yellow);
    expect(ink.r).toBe(22);
    expect(contrastRatio(ink, yellow)).toBeGreaterThan(4.5);
  });

  it('always clears the AA floor on the four CombatDen role colours', () => {
    for (const color of [
      rgba(212, 12, 26, 1),
      rgba(10, 10, 12, 1),
      rgba(220, 231, 240, 1),
      rgba(0, 117, 142, 1),
    ]) {
      expect(contrastRatio(readableInk(color), color)).toBeGreaterThanOrEqual(4.5);
    }
  });
});

describe('relativeLuminance', () => {
  it('is 0 at black and 1 at white', () => {
    expect(relativeLuminance(rgba(0, 0, 0, 1))).toBeCloseTo(0, 5);
    expect(relativeLuminance(rgba(255, 255, 255, 1))).toBeCloseTo(1, 5);
  });

  it('gives the 21:1 extreme', () => {
    expect(contrastRatio(rgba(0, 0, 0, 1), rgba(255, 255, 255, 1))).toBeCloseTo(21, 2);
  });
});

describe('over', () => {
  it('composites a translucent derivation onto the theme ground', () => {
    // 12.6% of the brand red over near-black is the dim panel the app draws,
    // not the pale tint this page's white chrome would have produced.
    const flattened = over(rgba(212, 12, 26, 0.126), rgba(10, 10, 12, 1));
    expect(flattened.a).toBe(1);
    expect(flattened.r).toBe(35);
    expect(flattened.g).toBe(10);
    expect(flattened.b).toBe(14);
  });

  it('leaves an opaque colour untouched', () => {
    expect(over(rgba(1, 2, 3, 1), rgba(9, 9, 9, 1))).toEqual(rgba(1, 2, 3, 1));
  });
});

describe('buildInspection', () => {
  it('reads the artifact identity', () => {
    expect(inspection.appId).toBe('combatden');
    expect(inspection.designName).toBe('Apex MMA');
    expect(inspection.category).toBe('Fighting');
    expect(inspection.colorMode).toBe('dark');
    expect(inspection.background).toEqual(rgba(10, 10, 12, 1));
  });

  it('keeps the font prose that the rest of the app never renders either', () => {
    const display = inspection.fonts[0];
    expect(display?.slot).toBe('display');
    expect(display?.value?.family).toBe('Space Grotesk');
    expect(display?.value?.category).toBe('sans-serif');
    expect(display?.value?.displayName).toBe('Athletic Modern');
    expect(display?.value?.description).toBe(
      'A confident geometric sans with sharp proportions.',
    );
    // A face with no prose is still a produced face; only its prose is a hole.
    expect(inspection.fonts[1]?.value?.family).toBe('Roboto Flex');
    expect(inspection.fonts[1]?.value?.description).toBe('');
  });

  it('carries each image complexity tier beside its URL', () => {
    const logo = inspection.images.find((image) => image.slot === 'logo_primary');
    expect(logo?.value?.url).toBe('https://cdn/logo.png');
    expect(logo?.value?.complexity).toBe('high');
  });

  it('keeps the prose that the rest of the app never renders', () => {
    const primary = inspection.roles[0];
    expect(primary?.slot).toBe('primary');
    expect(primary?.displayName).toBe('Red Corner');
    expect(primary?.description).toBe('A bold, saturated competition red.');
  });

  it('lists every EXPECTED role, holes included', () => {
    expect(inspection.roles.map((role) => role.slot)).toEqual([
      'primary',
      'background',
      'text',
      'accent',
    ]);
    // `text` and `accent` are absent from the payload: present, but empty.
    expect(inspection.roles[2]?.color).toBeNull();
    expect(inspection.roles[2]?.description).toBe('');
  });

  it('lists all seven derivations per role in contract order', () => {
    for (const role of inspection.roles) {
      expect(role.derivations.map((d) => d.key)).toEqual([...DERIVATION_ORDER]);
    }
    // `background` only produced `light`; the other six are holes, not missing.
    const background = inspection.roles[1];
    expect(background?.derivations).toHaveLength(7);
    expect(background?.derivations.filter((d) => d.color !== null)).toHaveLength(1);
  });

  it('exposes the role own regular_text as its label colour', () => {
    expect(inspection.roles[0]?.onColor).toEqual(rgba(220, 231, 240, 1));
    expect(inspection.roles[1]?.onColor).toBeNull();
  });

  it('holds a slot for every expected image, font, text and icon', () => {
    expect(inspection.images).toHaveLength(10);
    expect(inspection.fonts).toHaveLength(2);
    expect(inspection.texts).toHaveLength(5);
    expect(inspection.icons).toHaveLength(4);
    expect(inspection.images.find((i) => i.slot === 'giftbox')?.value).toBeNull();
    expect(inspection.texts.find((t) => t.slot === 'reserve_cta')?.value).toBe('Lock it in');
  });

  it('counts only what was actually produced', () => {
    expect(inspection.counts).toEqual({
      roles: 2,
      derivations: 8,
      paletteTokens: 6,
      images: 1,
      fonts: 2,
      texts: 1,
      icons: 1,
      // The fixture declares no `format_set`, which is the shape of every run
      // generated before the pipeline chose arrangements.
      formats: 0,
    });
  });

  it('reads arrangements off the payload, since the browser has no format manifest', () => {
    const withFormats = wireTheme();
    (withFormats as Record<string, unknown>)['format_set'] = {
      formats: {
        // Deliberately out of order: the section sorts so two runs of one app
        // list their surfaces identically.
        rank_format: { value: 'beltHero' },
        home_format: { value: 'timeSpine' },
        // An empty pick means "no override", exactly as an empty text does. It
        // is dropped by the parser, so it never reaches the slot list — the
        // section reports what the run CHOSE, and a surface left at its shipped
        // arrangement was not a choice.
        videos_format: { value: '' },
      },
    };
    const built = buildInspection(parseThemeConfig(withFormats));

    expect(built.formats.map((f) => f.slot)).toEqual(['home_format', 'rank_format']);
    expect(built.formats.map((f) => f.value)).toEqual(['timeSpine', 'beltHero']);
    expect(built.counts.formats).toBe(2);
  });

  it('accepts an arrangement this build has never heard of', () => {
    // The vocabulary lives in the APP's app.yaml, not here. A value added there
    // must still reach a surface that prints it, or the inspector silently
    // under-reports what the engine produced.
    const exotic = wireTheme();
    (exotic as Record<string, unknown>)['format_set'] = {
      formats: { some_future_format: { value: 'aShapeNobodyHasBuiltYet' } },
    };
    const built = buildInspection(parseThemeConfig(exotic));

    expect(built.formats).toEqual([
      { slot: 'some_future_format', value: 'aShapeNobodyHasBuiltYet' },
    ]);
  });
});

describe('buildInspection on a theme that predates the new wire fields', () => {
  // A last-good copy stored by an older build, or a run whose output.yaml was
  // written before the pipeline stamped a category or a complexity tier. The
  // page must degrade — every count, family and URL still resolves off the flat
  // maps, and only the metadata beside them reads as absent.
  const legacy = wireTheme();
  delete (legacy as Record<string, unknown>)['category'];
  delete (legacy as Record<string, unknown>)['font_set'];
  delete (legacy as Record<string, unknown>)['image_set'];
  const degraded = buildInspection(parseThemeConfig(legacy));

  it('still counts every produced slot', () => {
    expect(degraded.counts).toEqual(inspection.counts);
  });

  it('keeps each font family and reads its prose as absent', () => {
    expect(degraded.fonts[0]?.value?.family).toBe('Space Grotesk');
    expect(degraded.fonts[0]?.value?.category).toBe('');
    expect(degraded.fonts[0]?.value?.displayName).toBe('');
    expect(degraded.fonts[0]?.value?.description).toBe('');
  });

  it('keeps each image URL and reads its tier as absent', () => {
    const logo = degraded.images.find((image) => image.slot === 'logo_primary');
    expect(logo?.value?.url).toBe('https://cdn/logo.png');
    expect(logo?.value?.complexity).toBe('');
  });

  it('reads the run category as absent rather than inventing one', () => {
    expect(degraded.category).toBe('');
  });
});

describe('groupPalette', () => {
  const groups = groupPalette(
    parseThemeConfig(wireTheme()).palette,
  );

  it('groups by role, then the shared surface tokens', () => {
    expect(groups.map((group) => group.label)).toEqual([
      'primary',
      'background',
      'shared',
      'other',
    ]);
  });

  it('orders a role base-first, then its derivations', () => {
    expect(groups[0]?.entries.map((entry) => entry.key)).toEqual([
      'primary',
      'primary_second',
    ]);
  });

  it('surfaces a token this client has never heard of rather than dropping it', () => {
    expect(groups[3]?.entries.map((entry) => entry.key)).toEqual([
      'unexpected_future_token',
    ]);
  });

  it('claims every key exactly once', () => {
    const keys = groups.flatMap((group) => group.entries.map((entry) => entry.key));
    expect(new Set(keys).size).toBe(keys.length);
    expect(keys).toHaveLength(6);
  });
});

describe('spectrumBands', () => {
  const bands = spectrumBands(inspection.roles, inspection.background);

  it('drops the holes and the base colours, keeping produced derivations', () => {
    expect(bands).toHaveLength(8);
    expect(bands.every((band) => band.key !== band.role)).toBe(true);
  });

  it('hands back colours already composited, so nothing renders translucent', () => {
    expect(bands.every((band) => band.color.a === 1)).toBe(true);
  });

  it('stays in role order', () => {
    expect(bands[0]?.role).toBe('primary');
    expect(bands.at(-1)?.role).toBe('background');
  });
});
