// The app chrome's tokens exist in two places on purpose: as TypeScript, for
// the ported GWNav/GWButton whose inline `style={{}}` objects must stay
// byte-comparable with LandingPage/hifi/chrome.jsx, and as CSS custom
// properties, for every CSS Module in the app. That duplication is the drift
// hazard this file exists to close: it parses ../styles/tokens.css and asserts
// each declared value still equals the module's.

import { readFileSync } from 'node:fs';
import { cwd } from 'node:process';

import { describe, expect, it } from 'vitest';

import { ADM } from '../tokens/adminTokens';
import { GW } from '../tokens/gw';

// Read off disk, not through `import '…tokens.css?raw'`: vitest runs with
// `css: false`, which hands back an EMPTY module for any `.css` request —
// `?raw` included — so the import would silently assert against ''.
const tokensCss = readFileSync(`${cwd()}/src/app/styles/tokens.css`, 'utf8');

/** Every `--name: value;` declared in the sheet. */
function declarations(css: string): Map<string, string> {
  const found = new Map<string, string>();
  for (const match of css.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)) {
    const [, name, value] = match;
    if (name !== undefined && value !== undefined) {
      found.set(name, value.trim().replace(/\s+/g, ' '));
    }
  }
  return found;
}

/** CSS is written with spaces after commas; the TS strings are not. */
function normalise(value: string): string {
  return value.toLowerCase().replace(/,\s+/g, ',').replace(/'/g, '"');
}

const declared = declarations(tokensCss);

describe('tokens.css mirrors the token modules', () => {
  it('parses the sheet', () => {
    expect(declared.size).toBeGreaterThan(50);
  });

  const gwCases: ReadonlyArray<readonly [string, string | number]> = [
    ['--gw-bg', GW.bg],
    ['--gw-bg-alt', GW.bgAlt],
    ['--gw-surface', GW.surface],
    ['--gw-ink', GW.ink],
    ['--gw-ink-soft', GW.inkSoft],
    ['--gw-ink-faint', GW.inkFaint],
    ['--gw-line', GW.line],
    ['--gw-line-soft', GW.lineSoft],
    ['--gw-accent', GW.accent],
    ['--gw-accent-dark', GW.accentDark],
    ['--gw-accent-soft', GW.accentSoft],
    ['--gw-accent-glow', GW.accentGlow],
    ['--gw-sans', GW.sans],
    ['--gw-mono', GW.mono],
    ['--gw-max-w', `${GW.maxW}px`],
  ];

  it.each(gwCases)('%s matches ds.jsx', (name, expected) => {
    expect(normalise(declared.get(name) ?? '')).toBe(normalise(String(expected)));
  });

  const admColourCases: ReadonlyArray<readonly [string, string]> = [
    ['--adm-ground', ADM.ground],
    ['--adm-surface', ADM.surface],
    ['--adm-ink', ADM.ink],
    ['--adm-text-2nd', ADM.text2nd],
    ['--adm-text-3rd', ADM.text3rd],
    ['--adm-line', ADM.line],
    ['--adm-line-soft', ADM.lineSoft],
    ['--adm-sapphire', ADM.sapphire],
    ['--adm-accent-dark', ADM.accentDark],
    ['--adm-on-accent', ADM.onAccent],
    ['--adm-card-shadow', ADM.cardShadow],
    ['--adm-button-shadow', ADM.buttonShadow],
    ['--adm-control-shadow', ADM.controlShadow],
    ['--adm-device-body', ADM.deviceBody],
    ['--adm-device-shadow', ADM.deviceShadow],
  ];

  it.each(admColourCases)('%s matches design_constants.dart', (name, expected) => {
    expect(normalise(declared.get(name) ?? '')).toBe(normalise(expected));
  });

  const admScaleCases: ReadonlyArray<readonly [string, number]> = [
    ['--adm-radius-big', ADM.radiusBig],
    ['--adm-radius-small', ADM.radiusSmall],
    ['--adm-radius-card', ADM.radiusCard],
    ['--adm-padding-big', ADM.paddingBig],
    ['--adm-padding-small', ADM.paddingSmall],
    ['--adm-space-big', ADM.spacingBig],
    ['--adm-space-large', ADM.spacingLarge],
    ['--adm-space-medium', ADM.spacingMedium],
    ['--adm-space-small', ADM.spacingSmall],
    ['--adm-space-tiny', ADM.spacingTiny],
    ['--adm-button-border', ADM.buttonBorder],
    ['--adm-button-border-size', ADM.buttonBorderSize],
    ['--adm-icon-big', ADM.iconSizeBig],
    ['--adm-icon-large', ADM.iconSizeLarge],
    ['--adm-icon-medium', ADM.iconSizeMedium],
    ['--adm-icon-small', ADM.iconSizeSmall],
    ['--adm-icon-tiny', ADM.iconSizeTiny],
    ['--adm-reward-card-title-height', ADM.rewardCardTitleHeight],
    ['--adm-spinner-size-large', ADM.spinnerSizeLarge],
    ['--adm-nav-height', ADM.navHeight],
    ['--adm-nav-max-width', ADM.navMaxWidth],
    ['--adm-h1-size', ADM.type.h1.size],
    ['--adm-h2-size', ADM.type.h2.size],
    ['--adm-h3-size', ADM.type.h3.size],
    ['--adm-p-size', ADM.type.p.size],
    ['--adm-p-big-size', ADM.type.pBig.size],
    ['--adm-p-small-size', ADM.type.pSmall.size],
    ['--adm-h1-tracking', ADM.type.h1.tracking],
    ['--adm-h2-tracking', ADM.type.h2.tracking],
    ['--adm-h3-tracking', ADM.type.h3.tracking],
    ['--adm-p-tracking', ADM.type.p.tracking],
  ];

  it.each(admScaleCases)('%s is the Dart value in px', (name, expected) => {
    expect(declared.get(name)).toBe(`${expected}px`);
  });

  const admWeightCases: ReadonlyArray<readonly [string, number]> = [
    ['--adm-h1-weight', ADM.type.h1.weight],
    ['--adm-h2-weight', ADM.type.h2.weight],
    ['--adm-h3-weight', ADM.type.h3.weight],
    ['--adm-p-weight', ADM.type.p.weight],
    ['--adm-p-big-weight', ADM.type.pBig.weight],
    ['--adm-p-small-weight', ADM.type.pSmall.weight],
    ['--adm-p-small-bold-weight', ADM.type.pSmallBold.weight],
  ];

  it.each(admWeightCases)('%s is unitless', (name, expected) => {
    expect(declared.get(name)).toBe(String(expected));
  });

  it('carries the Geist family in --adm-font', () => {
    expect(declared.get('--adm-font')).toContain(ADM.fontFamily);
  });

  it('declares NO showcase (--sc-*) token: the island owns its own', () => {
    expect([...declared.keys()].filter((name) => name.startsWith('--sc-'))).toEqual([]);
  });
});
