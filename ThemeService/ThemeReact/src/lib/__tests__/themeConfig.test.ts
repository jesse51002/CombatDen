// Covers ../models/themeConfig.ts + themeStyle(sPage).ts — the port of
// ../../../../ThemeFlutter/lib/data/models/customization*.dart parsing.

import { describe, expect, it } from 'vitest';

import { parseThemeConfig } from '../models/themeConfig';
import { parseThemeStylesPage } from '../models/themeStylesPage';

import { APEX_MMA_PAYLOAD, STYLES_PAGE_PAYLOAD } from './fixtures/apexmma';

const resolve = (raw: string): string =>
  raw.startsWith('http') ? raw : `http://localhost:8001${raw}`;

describe('parseThemeConfig against the real ApexMMA wire shape', () => {
  const config = parseThemeConfig(APEX_MMA_PAYLOAD);

  it('reads the top-level identity fields', () => {
    expect(config.app).toBe('combatden');
    expect(config.displayName).toBe('CombatDen');
    expect(config.designName).toBe('Apex MMA');
    expect(config.colorMode).toBe('dark');
  });

  it('reads colours from the rgb block, treating a null alpha as opaque', () => {
    expect(config.colors['primary']?.color).toEqual({ r: 212, g: 12, b: 26, a: 1 });
    expect(config.colors['primary']?.displayName).toBe('Red Corner');
  });

  it('keeps all seven derivations, alpha included', () => {
    const derivations = config.colors['primary']?.derivations ?? {};
    expect(Object.keys(derivations).sort()).toEqual([
      'card',
      'dark',
      'light',
      'popup',
      'regular_text',
      'second',
      'third',
    ]);
    expect(derivations['second']).toEqual({ r: 212, g: 12, b: 26, a: 0.75 });
    expect(derivations['card']).toEqual({ r: 212, g: 12, b: 26, a: 0.126 });
  });

  it('parses the flat palette, which carries bare ColorValues', () => {
    expect(config.palette['card']).toEqual({ r: 220, g: 231, b: 234, a: 0.113 });
    expect(config.palette['background']).toEqual({ r: 10, g: 6, b: 4, a: 1 });
    expect(config.palette['accent_second']?.a).toBe(0.75);
  });

  it('keeps a colour slot whose colour block is unparseable, with a null colour', () => {
    // Lossy-tolerant, not fatal: the slot survives so its display name is still
    // readable, and every resolver falls back on the missing colour.
    expect(config.colors['broken']).toBeDefined();
    expect(config.colors['broken']?.color).toBeNull();
  });

  it('reads the run classification bucket', () => {
    expect(config.category).toBe('Fighting');
  });

  it('collapses images / fonts / icons to flat maps and drops empty slots', () => {
    expect(config.images['logo_primary']).toContain('logo_primary.png');
    expect(config.images['trophy_image']).toBeUndefined();
    expect(config.fonts['body']).toBe('Roboto Flex');
    expect(config.fonts['display']).toBe('Space Grotesk');
    expect(config.icons['nav_home']).toContain('nav_home');
  });

  it('reads each image complexity tier, skipping a slot that has none', () => {
    expect(config.imageComplexity['logo_primary']).toBe('high');
    expect(config.imageComplexity['celebration_image']).toBe('high');
    expect(config.imageComplexity['trophy_image']).toBeUndefined();
  });

  it('keeps the font prose the flat map has nowhere to put', () => {
    const display = config.fontFaces['display'];
    expect(display?.family).toBe('Space Grotesk');
    expect(display?.category).toBe('sans-serif');
    expect(display?.displayName).toBe('Athletic Modern');
    expect(display?.description).toContain('confident geometric sans');
    expect(config.fontFaces['body']?.displayName).toBe('Professional Grotesque');
  });

  it('unwraps text_set.texts and drops empty copy', () => {
    expect(config.texts['class_booked_headline']).toBe("You're in.");
    expect(config.texts['reserve_cta']).toBe('Lock it in');
    expect(config.texts['wins_title']).toBeUndefined();
  });
});

describe('parseThemeConfig lossy tolerance', () => {
  it('never throws on garbage, degrading every section to empty', () => {
    for (const raw of [null, undefined, 42, 'nope', [], {}]) {
      const config = parseThemeConfig(raw);
      expect(config.app).toBe('');
      expect(config.designName).toBe('');
      expect(config.category).toBe('');
      expect(config.colorMode).toBe('dark');
      expect(config.colors).toEqual({});
      expect(config.palette).toEqual({});
      expect(config.images).toEqual({});
      expect(config.imageComplexity).toEqual({});
      expect(config.fonts).toEqual({});
      expect(config.fontFaces).toEqual({});
      expect(config.texts).toEqual({});
      expect(config.icons).toEqual({});
    }
  });

  it('parses a payload written before category / font_set / image_set existed', () => {
    // The exact shape of a `customization_last_good_json` written by a build
    // that predates this change: every OLD field resolves, every NEW one
    // degrades. A returning visitor must not need a network round-trip to get
    // their theme back, so this is the case that has to keep working.
    const legacy = { ...APEX_MMA_PAYLOAD };
    delete legacy['category'];
    delete legacy['font_set'];
    delete legacy['image_set'];

    const config = parseThemeConfig(legacy);
    expect(config.designName).toBe('Apex MMA');
    expect(config.fonts['display']).toBe('Space Grotesk');
    expect(config.images['logo_primary']).toContain('logo_primary.png');
    expect(config.colors['primary']?.color).toEqual({ r: 212, g: 12, b: 26, a: 1 });
    expect(config.category).toBe('');
    expect(config.fontFaces).toEqual({});
    expect(config.imageComplexity).toEqual({});
  });

  it('drops a font face with no family, keeping the flat map authoritative', () => {
    // "Absent" and "present but blank" stay one case, exactly as an empty
    // image URL does — a surface never has to test for both.
    const config = parseThemeConfig({
      fonts: { display: 'Space Grotesk' },
      font_set: {
        fonts: {
          display: { family: '', category: 'sans-serif', display_name: 'Ghost' },
          body: { family: 'Inter' },
        },
      },
    });
    expect(config.fontFaces['display']).toBeUndefined();
    expect(config.fonts['display']).toBe('Space Grotesk');
    expect(config.fontFaces['body']).toEqual({
      family: 'Inter',
      category: '',
      displayName: '',
      description: '',
    });
  });

  it('skips only the malformed slot, keeping its neighbours', () => {
    const config = parseThemeConfig({
      color_set: {
        colors: { good: { color: { rgb: { r: 1, g: 2, b: 3 } } }, bad: 'not-an-object' },
        palette: { good: { rgb: { r: 4, g: 5, b: 6 } }, bad: 7 },
      },
      images: { good: '/a.png', bad: 12 },
      text_set: { texts: { good: { value: 'hi' }, bad: { value: 9 } } },
    });
    expect(config.colors['good']?.color).toEqual({ r: 1, g: 2, b: 3, a: 1 });
    expect(config.colors['bad']).toBeUndefined();
    expect(config.palette['good']).toBeDefined();
    expect(config.palette['bad']).toBeUndefined();
    expect(config.images).toEqual({ good: '/a.png' });
    expect(config.texts).toEqual({ good: 'hi' });
  });

  it('defaults an absent or unknown colour mode to dark, matching the fallback palette', () => {
    expect(parseThemeConfig({ color_set: {} }).colorMode).toBe('dark');
    expect(parseThemeConfig({ color_set: { mode: 'sepia' } }).colorMode).toBe('dark');
    expect(parseThemeConfig({ color_set: { mode: 'LIGHT' } }).colorMode).toBe('light');
  });
});

describe('parseThemeStylesPage', () => {
  it('absolutises relative card art and passes absolute URLs through', () => {
    const page = parseThemeStylesPage(STYLES_PAGE_PAYLOAD, resolve);
    expect(page.items).toHaveLength(2);
    expect(page.items[0]?.id).toBe('ApexMMA');
    expect(page.items[0]?.celebrationImageUrl).toBe(
      'http://localhost:8001/apps/combatden/ApexMMA/images/celebration_image',
    );
    expect(page.items[1]?.celebrationImageUrl).toBe(
      'https://cdn.combatden.net/combatden/ZenBJJ/images/celebration_image.png',
    );
    expect(page.total).toBe(76);
  });

  it('carries no gymId — ThemeService styles have no gym', () => {
    const page = parseThemeStylesPage(STYLES_PAGE_PAYLOAD, resolve);
    expect(Object.keys(page.items[0] ?? {}).sort()).toEqual([
      'category',
      'celebrationImageUrl',
      'displayName',
      'id',
    ]);
  });

  it('drops an item with no id and degrades a broken envelope to empty', () => {
    const page = parseThemeStylesPage({ items: [{ display_name: 'orphan' }, 'junk'] }, resolve);
    expect(page.items).toEqual([]);
    expect(page.total).toBe(0);

    const broken = parseThemeStylesPage(null, resolve);
    expect(broken.items).toEqual([]);
    expect(broken.limit).toBe(0);
  });
});