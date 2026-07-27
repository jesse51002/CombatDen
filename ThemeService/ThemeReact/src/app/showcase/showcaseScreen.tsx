// Ports ../../../../../CRM/lib/showcase/showcase_screen.dart: the seven
// member-app surfaces previewable in the live theme preview, in slideshow
// order, their short human labels, and the fan-out that builds each one.
//
// TWO ARE REAL, FIVE ARE STILL PLACEHOLDERS. `home` and `booking` render the
// ported member-app screens; the other five keep the theming-proof placeholder
// below until their own ports land beside this file. The placeholder is not
// filler: every value it paints resolves LIVE, so a wrong or unloaded theme
// shows up immediately rather than at integration time.
//
// Gym identity (`gymName` / `gymLogoSrc`) is NOT a customization slot — it is
// the host's, passed in as arguments, and only the surfaces that render the gym
// header consume it. This app is the PUBLIC browser and has no gym, which is
// why `themeTabPreview` is on: with no host logo the topbar falls through to
// the active theme's own `logo_primary`, so switching theme re-logos the mock.
//
// Everything below obeys the showcase island's import rule (eslint.config.js
// Gate 2a): `theme-react`, this island, and nothing from ../chrome, ../browser,
// ../widgets or ../tokens. The surrounding admin chrome uses the SAME token
// names with different values, which is exactly the mix-up the gate prevents.

import { BookingShowcase } from './BookingShowcase';
import { HomeShowcase } from './home/HomeShowcase';
import styles from './showcaseScreen.module.css';
import { ShowcaseThemeVars } from './ShowcaseThemeVars';
import { useShowcaseContent } from './useShowcaseContent';

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

/** `ShowcaseScreen.build`'s `gymName` default. */
const DEFAULT_GYM_NAME = 'Your Gym';

export interface ShowcaseScreenViewProps {
  screen: ShowcaseScreen;
  /**
   * The previewed style's showcase category (`Fighting`, `Yoga`, …), which
   * picks the demo classes and rewards the phone fills with. Null falls back to
   * the default group, exactly as Dart does when no category is known yet.
   *
   * The browser's own `selectedStyle` store already tracks it, but the showcase
   * island may not import from ../browser (Gate 2a), so it arrives as a prop.
   * Until ../browser/ThemePreviewPane.tsx threads it through, every theme
   * previews the default group's content.
   */
  category?: string | null;
  /** The host gym's name. There is no gym in this browser. */
  gymName?: string;
  /** The host gym's real logo URL. Absent here, which is what arms the ladder. */
  gymLogoSrc?: string | undefined;
}

/**
 * One previewable surface, rendered at the phone's real 390x844 screen size.
 *
 * <ShowcaseThemeVars> is the root: it writes the whole `--sc-*` token surface
 * onto this one element, and every stylesheet below reads only those variables.
 * A theme switch therefore re-skins the screen by rewriting variables here.
 */
export function ShowcaseScreenView({
  screen,
  category = null,
  gymName = DEFAULT_GYM_NAME,
  gymLogoSrc,
}: ShowcaseScreenViewProps) {
  const { classes } = useShowcaseContent(category);

  return (
    <ShowcaseThemeVars className={styles.root}>
      {screen === 'home' ? (
        <HomeShowcase
          gymName={gymName}
          gymLogoSrc={gymLogoSrc}
          classes={classes}
          themeTabPreview
        />
      ) : screen === 'booking' ? (
        <BookingShowcase />
      ) : (
        <PlaceholderScreen screen={screen} />
      )}
    </ShowcaseThemeVars>
  );
}

/** The palette roles the placeholder shows, so an unresolved slot is obvious. */
const SWATCHES: readonly string[] = Object.freeze([
  '--sc-primary',
  '--sc-accent',
  '--sc-card',
  '--sc-text',
]);

const SWATCH_LABELS: readonly string[] = Object.freeze(['primary', 'accent', 'card', 'text']);

/**
 * The five surfaces whose ports have not landed. Explicitly labelled as a
 * placeholder, and painted entirely from the live `--sc-*` variables — so it is
 * also the cheapest proof that the theming pipeline reaches inside the phone.
 */
function PlaceholderScreen({ screen }: { screen: ShowcaseScreen }) {
  const label = SHOWCASE_SCREEN_LABELS[screen];
  return (
    <div className={styles.screen}>
      <p className={styles.eyebrow}>Placeholder</p>
      <h2 className={styles.title}>{label}</h2>
      <p className={styles.body}>
        The real {label.toLowerCase()} surface lands next. Everything you see here — the canvas, the
        ink, both font slots and the swatches below — is resolved live from the selected theme.
      </p>

      <div className={styles.swatches}>
        {SWATCHES.map((token, i) => (
          <div key={token} className={styles.swatch}>
            <span className={styles.chip} style={{ background: `var(${token})` }} />
            <span className={styles.chipLabel}>{SWATCH_LABELS[i]}</span>
          </div>
        ))}
      </div>

      <div className={styles.cta}>Primary action</div>
    </div>
  );
}
