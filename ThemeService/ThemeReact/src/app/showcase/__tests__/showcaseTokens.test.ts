// The showcase island's token surface (../showcaseTokens.ts, porting
// CRM/lib/showcase/showcase_tokens.dart).
//
// Two things are pinned here, and both are things a reviewer cannot eyeball:
//
//  1. THE DERIVED FALLBACKS. `_darkPrimaryFallback`, `_liveSurfaceFallback`,
//     `divider`'s alpha ramp and `popup`'s alpha blend are real arithmetic on
//     the Dart side, ported by hand. They only ever render when NOTHING has
//     loaded, which is exactly when nobody is looking — so the numbers are
//     asserted against the values the Dart maths produces.
//  2. THE TWO-TOKEN-SYSTEM RULE. `radiusBig` is 32 here and 12 in the admin
//     chrome. A test that fails the moment the two are "unified" is cheaper
//     than the review that catches it.
//
// This file lives under src/app/showcase/ rather than src/app/__tests__/
// because eslint Gate 2b forbids anything outside the island from importing
// `showcase/showcaseTokens` — a test there could not import its own subject.

import { describe, expect, it } from 'vitest';

import {
  BAD_RED,
  FALLBACK_FONT_FAMILY,
  GOOD_GREEN,
  HYPERLINK,
  OK_YELLOW,
  SC,
  accent,
  backgroundColor,
  card,
  darkPrimary,
  divider,
  popup,
  primaryButtonText,
  primaryCard,
  primaryColor,
  primaryColor50,
  showcaseCssVars,
  text,
  text2nd,
  text3rd,
} from '../showcaseTokens';

// Nothing is registered in this file, so every resolver takes its fallback —
// which is precisely the branch under test.
const NO_THEME = Object.freeze({
  config: null,
  activeDesignId: null,
  isLoaded: false,
  isReady: false,
});

describe('brand fallbacks', () => {
  it('is CombatDen verbatim', () => {
    expect(primaryColor()).toEqual({ r: 255, g: 108, b: 45, a: 1 });
    expect(backgroundColor()).toEqual({ r: 18, g: 22, b: 25, a: 1 });
    expect(text()).toEqual({ r: 244, g: 243, b: 238, a: 1 });
    expect(accent()).toEqual({ r: 225, g: 183, b: 92, a: 1 });
    expect(FALLBACK_FONT_FAMILY).toBe('Jura');
  });

  it('keeps the status colours off the brand', () => {
    expect(HYPERLINK).toEqual({ r: 131, g: 199, b: 255, a: 1 });
    expect(GOOD_GREEN).toEqual({ r: 116, g: 243, b: 148, a: 1 });
    expect(OK_YELLOW).toEqual({ r: 204, g: 206, b: 68, a: 1 });
    expect(BAD_RED).toEqual({ r: 249, g: 74, b: 77, a: 1 });
  });
});

describe('derived fallbacks', () => {
  it('re-lights the primary to 42% for darkPrimary', () => {
    // HSLColor.fromColor(#FF6C2D) is (h 18, s 1, l 0.5882); withLightness(
    // 0.5882 * 0.42 = 0.2471).toColor() lands on #7E2600.
    expect(darkPrimary()).toEqual({ r: 126, g: 38, b: 0, a: 1 });
  });

  it('takes the alpha derivations of primary and text', () => {
    expect(primaryColor50()).toEqual({ r: 255, g: 108, b: 45, a: 0.5 });
    expect(primaryCard()).toEqual({ r: 255, g: 108, b: 45, a: 0.09 });
    expect(text2nd()).toEqual({ r: 244, g: 243, b: 238, a: 0.75 });
    expect(text3rd()).toEqual({ r: 244, g: 243, b: 238, a: 0.5 });
    // `regular_text` falls back to the plain ink, not to a computed contrast.
    expect(primaryButtonText()).toEqual({ r: 244, g: 243, b: 238, a: 1 });
  });

  it('tunes the card surface to the LIVE canvas lightness', () => {
    // alpha = 0.06 + 0.5 * (lightness(background) / 0.9), background #121619
    // having lightness 0.08431.
    const surface = card();
    expect(surface.r).toBe(255);
    expect(surface.g).toBe(255);
    expect(surface.b).toBe(255);
    expect(surface.a).toBeCloseTo(0.10684, 5);
  });

  it('flattens that surface over the canvas for popup', () => {
    expect(popup()).toEqual({ r: 43, g: 47, b: 50, a: 1 });
  });

  it('ramps the divider alpha with the canvas, clamped to [0.10, 0.22]', () => {
    const line = divider();
    expect(line.r).toBe(244);
    // 0.10 + 0.10 * 0.08431 = 0.10843, inside the clamp.
    expect(line.a).toBeCloseTo(0.10843, 5);
  });
});

describe('the two token systems never meet', () => {
  it('keeps the MEMBER app scale, not the admin chrome one', () => {
    // ../tokens/adminTokens.ts has radiusBig 12. This is the phone.
    expect(SC.radiusBig).toBe(32);
    expect(SC.radiusSmall).toBe(16);
    expect(SC.screenHorizontalPadding).toBe(16);
    expect(SC.spacingBig).toBe(32);
    expect(SC.iconSizeMd).toBe(24);
  });
});

describe('showcaseCssVars', () => {
  const vars = showcaseCssVars(NO_THEME, 'Oswald', 'Inter');

  it('namespaces every variable under --sc-', () => {
    const keys = Object.keys(vars);
    expect(keys.length).toBeGreaterThan(60);
    expect(keys.every((key) => key.startsWith('--sc-'))).toBe(true);
  });

  it('writes both font stacks from the slots it was handed', () => {
    expect(vars['--sc-font-body']).toBe('"Inter", system-ui, sans-serif');
    expect(vars['--sc-font-display']).toBe('"Oswald", system-ui, sans-serif');
  });

  it('spells letterSpacing in PX, never em', () => {
    // Flutter's letterSpacing is absolute logical px; `-0.02em` at 24px would
    // be -0.48px, ~24x tighter. See ../../../CLAUDE.md "Things that will bite".
    expect(vars['--sc-type-h1-ls']).toBe('-0.02px');
    expect(vars['--sc-type-p-ls']).toBe('0.03px');
    expect(vars['--sc-type-h2-ls']).toBe('0px');
  });

  it('never sets a numeric line-height — Flutter leaves `height:` unset', () => {
    for (const [key, value] of Object.entries(vars)) {
      if (!key.startsWith('--sc-type-') || key.endsWith('-ls')) continue;
      expect(value).toContain('/normal ');
    }
  });

  it('carries the ramp at the Dart weights and sizes', () => {
    expect(vars['--sc-type-h1']).toBe('700 24px/normal "Inter", system-ui, sans-serif');
    expect(vars['--sc-type-h2-bold']).toBe('700 16px/normal "Inter", system-ui, sans-serif');
    expect(vars['--sc-type-h3']).toBe('600 13px/normal "Inter", system-ui, sans-serif');
    expect(vars['--sc-type-p-small']).toBe('400 11px/normal "Inter", system-ui, sans-serif');
    // The hero numerals are the DISPLAY slot.
    expect(vars['--sc-type-big1']).toBe('600 160px/normal "Oswald", system-ui, sans-serif');
    expect(vars['--sc-type-big2']).toBe('600 32px/normal "Oswald", system-ui, sans-serif');
  });

  it('defaults the canvas to dark when nothing is loaded', () => {
    expect(vars['--sc-canvas']).toBe('dark');
    expect(showcaseCssVars({ ...NO_THEME }, 'A', 'B')['--sc-canvas']).toBe('dark');
  });
});
