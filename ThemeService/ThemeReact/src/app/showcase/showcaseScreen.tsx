// Ports ../../../../../CRM/lib/showcase/showcase_screen.dart: the member-app
// surfaces previewable in the live theme preview, in slideshow order, their
// short human labels, and the fan-out that builds each one.
//
// NINE SURFACES, SEVEN OF THEM FROM THE DART ENUM. `video` and `profile` have
// no entry there: the Flutter preview never carried them, so ./videos/ and
// ./profile/ are first ports straight from `MobileApp/lib/features/`. They are
// what make the preview's claim checkable — a theme that only ever repaints
// seven single-viewport compositions is demonstrating a palette, whereas two
// deep, scrolling, app-shaped screens are demonstrating an app. `profile` also
// carries the only consumer of the `next_rank_belt_image` slot, which the
// pipeline has generated for all 76 themes and nothing had ever rendered.
//
// Gym identity (`gymName` / `gymLogoSrc`) is NOT a customization slot — it is
// the host's, passed in as arguments, and only the surfaces that render the gym
// header consume it. This app is the PUBLIC browser and has no gym, which is
// why `themeTabPreview` is on: with no host logo the topbar falls through to
// the active theme's own `logo_primary`, so switching theme re-logos the mock.
//
// The gym CONTENT ladder is the other half of that: `useShowcaseContent`
// resolves the previewed category's demo classes, rewards and video feed
// (network → bundled) once here, and hands the classes to `home`, the rewards
// to both rewards surfaces — the same list, rendered as a cover flow on one and
// as store cards on the other — and the feed to `video` and `profile`.
//
// Everything below obeys the showcase island's import rule (eslint.config.js
// Gate 2a): `theme-react`, this island, and nothing from ../chrome, ../browser,
// ../widgets or ../tokens. The surrounding admin chrome uses the SAME token
// names with different values, which is exactly the mix-up the gate prevents.

import type { ReactElement } from 'react';

import { BookingShowcase } from './BookingShowcase';
import { HomeShowcase } from './home/HomeShowcase';
import { PointsShowcase } from './PointsShowcase';
import { ProfileShowcase } from './profile/ProfileShowcase';
import { RewardsCardShowcase } from './RewardsCardShowcase';
import { RewardsShowcase } from './RewardsShowcase';
import styles from './showcaseScreen.module.css';
import { ShowcaseThemeVars } from './ShowcaseThemeVars';
import { StatsShowcase } from './StatsShowcase';
import { useShowcaseContent } from './useShowcaseContent';
import { VideoShowcase } from './videos/VideoShowcase';
import { WinsShowcase } from './WinsShowcase';

/** The member-app surfaces previewable in the live theme preview. */
export type ShowcaseScreen =
  | 'home'
  | 'booking'
  | 'wins'
  | 'points'
  | 'rewards'
  | 'streak'
  | 'store'
  | 'video'
  | 'profile';

/**
 * In slideshow order — `ShowcaseScreen.values`, plus the two new surfaces.
 *
 * THE ORDER IS A NARRATIVE, NOT A LIST. The seven ported screens already tell
 * the member's arc in the Dart's own order: arrive (`home`), book (`booking`),
 * finish the class and collect (`wins` → `points` → `rewards` → `streak`), then
 * spend (`store`). The two new screens are the parts of that arc the Flutter
 * preview could not show — what a member does BETWEEN classes (`video`) and
 * what all of it adds up to (`profile`) — so they sit at the end, after the
 * spend, where they read as the app's standing surfaces rather than as another
 * beat of the post-class celebration.
 *
 * Putting either of them earlier would also break the celebration RUN: `wins`
 * through `streak` are four looping animations that play as one sequence, and
 * dropping a static scrolling page into the middle of it reads as a stall.
 */
export const SHOWCASE_SCREENS: readonly ShowcaseScreen[] = Object.freeze([
  'home',
  'booking',
  'wins',
  'points',
  'rewards',
  'streak',
  'store',
  'video',
  'profile',
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
  video: 'Video',
  profile: 'Profile',
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
  const { classes, rewards, videos } = useShowcaseContent(category);

  // `ShowcaseScreen.build`'s switch. A switch rather than a ternary chain at
  // nine cases, and exhaustive over the union — a new surface fails to
  // typecheck here until it is built, which is what the placeholder used to
  // paper over.
  let surface: ReactElement;
  switch (screen) {
    case 'home':
      surface = (
        <HomeShowcase
          gymName={gymName}
          gymLogoSrc={gymLogoSrc}
          classes={classes}
          themeTabPreview
        />
      );
      break;
    case 'booking':
      surface = <BookingShowcase />;
      break;
    case 'wins':
      surface = <WinsShowcase />;
      break;
    case 'points':
      surface = <PointsShowcase />;
      break;
    case 'rewards':
      surface = <RewardsCardShowcase rewards={rewards} />;
      break;
    case 'streak':
      surface = <StatsShowcase />;
      break;
    case 'store':
      surface = <RewardsShowcase gymName={gymName} gymLogoSrc={gymLogoSrc} rewards={rewards} />;
      break;
    case 'video':
      surface = <VideoShowcase gymName={gymName} gymLogoSrc={gymLogoSrc} videos={videos} />;
      break;
    case 'profile':
      surface = <ProfileShowcase gymName={gymName} gymLogoSrc={gymLogoSrc} videos={videos} />;
      break;
  }

  return <ShowcaseThemeVars className={styles.root}>{surface}</ShowcaseThemeVars>;
}
