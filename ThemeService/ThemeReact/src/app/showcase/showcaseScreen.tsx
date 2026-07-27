// Ports the ENUM half of ../../../../../CRM/lib/showcase/showcase_screen.dart:
// the seven member-app surfaces previewable in the live theme preview, in
// slideshow order, and their short human labels.
//
// THE SCREENS THEMSELVES ARE STUBS. Dart's `ShowcaseScreen.build` fans out to
// seven self-contained widgets (HomeShowcase, BookingShowcase, …) that each
// theme and animate themselves; those are the next agent's work and will land
// beside this file. What is real here is the CONTRACT — the seven values, their
// order, their labels — and the proof that the theming pipeline reaches inside
// the phone: every placeholder below paints from the LIVE resolved theme
// (colours, both font slots, the logo image), so a wrong or unloaded theme is
// visible immediately rather than at integration time.
//
// This module obeys the showcase island's import rule (eslint.config.js Gate
// 2a): it may reach for `theme-react` and its own CSS, and for nothing in
// ../chrome, ../browser, ../widgets or ../tokens. The surrounding admin chrome
// uses the SAME token names with different values, which is exactly the mix-up
// the gate exists to prevent.

import { rgba, toCss, useThemeFontFamily, useThemeImageSrc, useThemeToken } from 'theme-react';
import type { CSSProperties } from 'react';

import styles from './showcaseScreen.module.css';

/** The member-app surfaces previewable in the live theme preview. */
export type ShowcaseScreen = 'home' | 'booking' | 'wins' | 'points' | 'rewards' | 'streak' | 'store';

/** In slideshow order — `ShowcaseScreen.values`. */
export const SHOWCASE_SCREENS: readonly ShowcaseScreen[] = Object.freeze([
  'home',
  'booking',
  'wins',
  'points',
  'rewards',
  'streak',
  'store',
] as const);

/** Short human label for the view selector / captions — `ShowcaseScreen.label`. */
export const SHOWCASE_SCREEN_LABELS: Readonly<Record<ShowcaseScreen, string>> = Object.freeze({
  home: 'Home',
  booking: 'Booking',
  wins: 'Achievements',
  points: 'Points',
  rewards: 'Rewards',
  streak: 'Streak',
  store: 'Store',
});

/**
 * The CombatDen fallbacks the runtime degrades to when NOTHING has loaded — a
 * dark gym canvas. They are the only hardcoded colours in the island, and
 * seeing them means the theme did not load, which is the point.
 */
const FALLBACK = {
  background: rgba(15, 16, 20),
  text: rgba(240, 241, 245),
  primary: rgba(212, 12, 26),
  accent: rgba(64, 132, 255),
  card: rgba(28, 30, 36),
} as const;

/** The palette roles the placeholder shows, so an unresolved slot is obvious. */
const SWATCHES: readonly string[] = Object.freeze(['primary', 'accent', 'card', 'text']);

export interface ShowcaseScreenViewProps {
  screen: ShowcaseScreen;
}

/**
 * One previewable surface, rendered at the phone's real 390×844 screen size.
 * A placeholder that is explicitly labelled as one — and that resolves every
 * value it draws through the live theme.
 */
export function ShowcaseScreenView({ screen }: ShowcaseScreenViewProps) {
  const background = useThemeToken('background', FALLBACK.background);
  const text = useThemeToken('text', FALLBACK.text);
  const primary = useThemeToken('primary', FALLBACK.primary);
  const accent = useThemeToken('accent', FALLBACK.accent);
  const card = useThemeToken('card', FALLBACK.card);
  const displayFont = useThemeFontFamily('display', 'system-ui');
  const bodyFont = useThemeFontFamily('body', 'system-ui');
  const logoUrl = useThemeImageSrc('logo_primary');

  const swatchColors: Record<string, string> = {
    primary: toCss(primary),
    accent: toCss(accent),
    card: toCss(card),
    text: toCss(text),
  };

  const style: CSSProperties = {
    background: toCss(background),
    color: toCss(text),
    fontFamily: `"${bodyFont}", system-ui, sans-serif`,
  };

  return (
    <div className={styles.screen} style={style}>
      {logoUrl !== '' && (
        <img
          key={logoUrl}
          className={styles.logo}
          src={logoUrl}
          alt=""
          onError={(event) => {
            event.currentTarget.style.display = 'none';
          }}
        />
      )}

      <p className={styles.eyebrow} style={{ color: toCss(primary) }}>
        Placeholder
      </p>
      <h2
        className={styles.title}
        style={{ fontFamily: `"${displayFont}", system-ui, sans-serif` }}
      >
        {SHOWCASE_SCREEN_LABELS[screen]}
      </h2>
      <p className={styles.body}>
        The real {SHOWCASE_SCREEN_LABELS[screen].toLowerCase()} surface lands next. Everything you
        see here — the canvas, the ink, the two font slots, the logo and the swatches below — is
        resolved live from the selected theme.
      </p>

      <div className={styles.swatches}>
        {SWATCHES.map((role) => (
          <div key={role} className={styles.swatch}>
            <span
              className={styles.chip}
              style={{ background: swatchColors[role], borderColor: toCss(text) }}
            />
            <span className={styles.chipLabel}>{role}</span>
          </div>
        ))}
      </div>

      <div className={styles.cta} style={{ background: toCss(primary) }}>
        <span style={{ fontFamily: `"${displayFont}", system-ui, sans-serif` }}>Primary action</span>
      </div>
    </div>
  );
}
