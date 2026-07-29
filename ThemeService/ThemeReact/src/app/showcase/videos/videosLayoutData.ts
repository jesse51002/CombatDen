// Ports ../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_layout_data.dart — everything a videos ARRANGEMENT renders, derived
// once so all five values are handed the identical payload.
//
// This is where the arrangement-only invariant is made STRUCTURAL rather than
// asserted: an arrangement is given this object and cannot reach past it, so it
// cannot fetch, re-sort, filter, or invent. Choosing an arrangement changes
// where these land, not what they are.
//
// WHAT DART CARRIES THAT THIS DOES NOT: the four callbacks
// (`onScopeSelected` / `onTabSelected` / `onVideoTap` / `onViewAll`). Every
// surface in this island is a preview inside a phone frame that takes no input
// — ../VideoCategoryTabs.tsx and ../rewards/RewardsTabs.tsx both reached the
// same conclusion — so there is nothing for an arrangement to wire them to. The
// affordances themselves are all still rendered; only the routes behind them
// are absent, which is a property of the browser, not of an arrangement.
//
// WHAT DART CALLS A TAG, THIS CALLS A GENRE. Dart's `VideosLayoutData.fromFeed`
// derives its filter from the coarse `big_groups` of the PRE-PORTAL feed model;
// the live screen this island ported (see ./videoSelectors.ts, "WHICH SELECTORS
// THESE ARE") filters on the fine-grained genre set instead. The shape is
// identical — a label list, a hero, one section per key — so the arrangements
// port unchanged; only the vocabulary underneath differs.

import type { ShowcaseVideo } from '../showcaseContent';

import type { VideoGenreSection } from './videoSelectors';
import { featuredVideo, genreLabel, genresInFeed, genreSections } from './videoSelectors';

/**
 * `tabGenres = [null, ...genres]` — "All" is this screen, so index 0 is always
 * the selected tab in a preview that cannot navigate.
 */
export function videoTabLabels(videos: readonly ShowcaseVideo[]): readonly string[] {
  return ['All', ...genresInFeed(videos).map(genreLabel)];
}

/** `VideosLayoutData` — the payload every arrangement is handed. */
export interface VideosLayoutData {
  /** "All" plus one label per genre the loaded feed carries. */
  readonly tabLabels: readonly string[];
  readonly selectedTabIndex: number;
  /** The hero: the top card of the already-ranked page, or null when empty. */
  readonly featured: ShowcaseVideo | null;
  /** One entry per genre present, in first-appearance order. */
  readonly sections: readonly VideoGenreSection[];
  /** The active filter holds nothing to show. */
  readonly isEmpty: boolean;
}

/** `VideosLayoutData.fromFeed` — derives the whole payload from a loaded feed. */
export function videosLayoutData(videos: readonly ShowcaseVideo[]): VideosLayoutData {
  const featured = featuredVideo(videos);
  const sections = genreSections(videos);
  return {
    tabLabels: videoTabLabels(videos),
    selectedTabIndex: 0,
    featured,
    sections,
    isEmpty: featured === null && sections.length === 0,
  };
}

/** `VideosLayoutData.titleOf` — the title a section renders. */
export function sectionTitle(section: VideoGenreSection): string {
  return genreLabel(section.genre);
}
