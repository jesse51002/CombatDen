// Ports ../../../../../../MobileApp/lib/features/videos/data/gym_video_selectors.dart
// and the `formatViewCount` / `metaLabel` half of `gym_video_helpers.dart` +
// `gym_video_card.dart`.
//
// Pure derivations over a loaded feed — no fetching, no re-sorting. The portal
// returns each page ALREADY ranked (personalized) server-side, so these
// preserve the given order rather than imposing one: the hero is the first
// card, and carousels group by genre in FIRST-APPEARANCE order.
//
// WHICH SELECTORS THESE ARE. `MobileApp/lib/features/videos/data/
// video_selectors.dart` is the RETIRED pre-portal set — it re-sorts client-side
// by `relevanceIndex` and its top filter is the coarse `big_groups`
// (educational / entertainment). The live `VideosScreen` has used
// `gym_video_selectors.dart` since the portal move, and its tab strip is the
// FINE-GRAINED genre set (`genresInFeed`), not `big_groups`. This port follows
// the live screen.
//
// THE APP OWNS NO GENRE VOCABULARY. Dart's `VideoGenre` enum exists to make a
// tab value the portal will accept back as `video_type`; nothing is sent back
// from a preview, so a genre here is the plain wire string and `genreLabel`
// ports `VideoGenre.label` (capitalise the first letter) rather than a lookup
// table that would have to track the enum.

import type { ShowcaseVideo } from '../showcaseContent';

/**
 * `VideoGenre.unknown` — the client-only resilient fallback for a value the app
 * does not recognise. It is never a real tab and never a carousel, so the
 * derivations below skip it exactly as Dart does.
 */
export const UNKNOWN_GENRE = 'unknown';

/** Ports `VideoGenre.label`: `professional` -> `Professional`. */
export function genreLabel(genre: string): string {
  if (genre === '') return genre;
  return `${genre.charAt(0).toUpperCase()}${genre.slice(1)}`;
}

/**
 * Ports `formatViewCount`: 168441 -> `168K`, 1_240_000 -> `1.2M`, 942 -> `942`.
 * Returns `''` when the count is hidden (null), so callers drop the "views"
 * clause entirely rather than printing "views" after nothing.
 */
export function formatViewCount(count: number | null): string {
  if (count === null) return '';
  if (count < 1000) return String(count);
  if (count < 1000000) return `${String(Math.floor(count / 1000))}K`;
  const millions = count / 1000000;
  // One decimal under 10M ("1.2M"), whole millions above ("12M").
  const label = millions < 10 ? millions.toFixed(1) : String(Math.floor(millions));
  return `${label}M`;
}

/**
 * Ports `GymVideoCard.metaLabel` — "Combat Culture ‧ 168K views", dropping the
 * views clause when the channel hides its stats. The separator is the Dart's
 * own U+2027 hyphenation point, not a bullet.
 */
export function videoMetaLabel(video: ShowcaseVideo): string {
  const views = formatViewCount(video.viewCount);
  return views === '' ? video.channelName : `${video.channelName} ‧ ${views} views`;
}

/**
 * Ports `genresInFeed`: the distinct real genres present, in first-appearance
 * order. Untagged cards and the `unknown` fallback are skipped, so a tab always
 * maps to a value the portal accepts as `video_type`.
 */
export function genresInFeed(videos: readonly ShowcaseVideo[]): readonly string[] {
  const seen = new Set<string>();
  const genres: string[] = [];
  for (const video of videos) {
    const genre = video.genre;
    if (genre === '' || genre === UNKNOWN_GENRE) continue;
    if (seen.has(genre)) continue;
    seen.add(genre);
    genres.push(genre);
  }
  return genres;
}

/**
 * Ports `featuredCard`: the hero is the top card of the already-ranked page, or
 * null when the page is empty.
 *
 * IT ALSO APPEARS IN ITS OWN CAROUSEL, and that is the real screen's behaviour,
 * not a porting slip: `videos_feed_body.dart` calls `featuredCard` and
 * `genreSections` over the SAME list and neither excludes the other's pick, so
 * the top video is both the hero and the first card of its genre row. Kept
 * verbatim — this island mirrors the member app rather than improving on it.
 */
export function featuredVideo(videos: readonly ShowcaseVideo[]): ShowcaseVideo | null {
  return videos.length === 0 ? null : (videos[0] ?? null);
}

/** One carousel: a genre and the cards claimed by it, in wire order. */
export interface VideoGenreSection {
  readonly genre: string;
  readonly videos: readonly ShowcaseVideo[];
}

/**
 * Ports `genreSections`: one carousel per genre present, in first-appearance
 * order, each holding that genre's cards in wire order. A card appears in
 * exactly one carousel — its single genre. Untagged / unknown cards belong to
 * no carousel and are dropped.
 */
export function genreSections(videos: readonly ShowcaseVideo[]): readonly VideoGenreSection[] {
  const order = genresInFeed(videos);
  const claimed = new Map<string, ShowcaseVideo[]>(order.map((genre) => [genre, []]));
  for (const video of videos) {
    const genre = video.genre;
    if (genre === '' || genre === UNKNOWN_GENRE) continue;
    claimed.get(genre)?.push(video);
  }
  return order
    .map((genre) => ({ genre, videos: claimed.get(genre) ?? [] }))
    .filter((section) => section.videos.length > 0);
}

/**
 * The Profile screen's "Videos to level up" slice — `LevelUpVideosSection`'s
 * own fetch, which asks the portal for `videoType: educational, limit: 10`.
 * There is no portal here, so the same narrowing is applied to the loaded feed.
 */
export const LEVEL_UP_GENRE = 'educational';

/** `_kLevelUpLimit` — a small page is plenty for the profile carousel. */
export const LEVEL_UP_LIMIT = 10;

/** The educational head of `videos`, capped at `LEVEL_UP_LIMIT`. */
export function levelUpVideos(videos: readonly ShowcaseVideo[]): readonly ShowcaseVideo[] {
  return videos.filter((video) => video.genre === LEVEL_UP_GENRE).slice(0, LEVEL_UP_LIMIT);
}
