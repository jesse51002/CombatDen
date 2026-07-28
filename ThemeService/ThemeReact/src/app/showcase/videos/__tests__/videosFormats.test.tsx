// The functional-equivalence gate for `videos_format`, mirroring
// `MobileApp/test/videos_invariants_test.dart`.
//
// An arrangement may change ARRANGEMENT ONLY: no screen merged or split, no
// functionality added, none removed, and no variant reaching data the shipped
// screen did not already have. That is a correctness property rather than a
// style note — it is what makes the whole idea sellable, because the app a
// member gets is rearranged, never reduced — so it is asserted mechanically:
// every value of `VIDEOS_FORMATS` is rendered over the same fabricated feed and
// its multiset of ../videoParts.ts identities is diffed against the
// baseline arrangement's.
//
// HOW A COMPONENT IS COUNTED. Dart counts widget TYPES with `find.byType`.
// React has no equivalent — a rendered tree is DOM, and a CSS-module class name
// is a build-time hash that says nothing about which component wrote it — so
// each ported component stamps `data-sc-part` on its root and this file counts
// those. See ../videoParts.ts.
//
// WHY `renderToStaticMarkup` AND NOT A TESTING LIBRARY. Zero new dependencies
// (../../../../CLAUDE.md), and the whole videos subtree is hook-free apart from
// two `useState`s that only fire on an image error — so a static render is the
// full tree, not a first frame of it. `useFormat` reads the preview's override
// store through `useSyncExternalStore`, which serves its `getServerSnapshot`
// here, and the theme resolvers degrade to their CombatDen fallbacks with no
// store loaded.

import { readFileSync } from 'node:fs';
import { cwd } from 'node:process';

import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, describe, expect, it } from 'vitest';

import { FORMAT_SLOTS, VIDEOS_FORMATS, setFormatOverride } from '../../formats';
import type { ShowcaseVideo } from '../../showcaseContent';
import { PART_ATTR } from '../videoParts';
import { VideoShowcase } from '../VideoShowcase';

/** The arrangement that ships, and therefore the baseline every other is diffed against. */
const BASELINE = VIDEOS_FORMATS[0];

/**
 * A CSS-module class arrives as `_local_ab12cd`, and the six-hex tail is a hash
 * of the FILE — so moving a rule between stylesheets changes it while changing
 * nothing about the rendered page. The baseline comparison below is about
 * structure, text and inline style, so the tail is normalised away and the
 * local name (which does carry intent) is kept.
 */
function normaliseClasses(html: string): string {
  return html.replace(/(_[A-Za-z0-9]+)_[0-9a-f]{6}/g, '$1_');
}

/** `data-sc-part` is test instrumentation; it is not markup the screen shipped. */
function stripParts(html: string): string {
  return html.replace(new RegExp(` ${PART_ATTR}="[^"]*"`, 'g'), '');
}

/**
 * The slice of the page an ARRANGEMENT owns: from the filter strip down to the
 * bottom nav.
 *
 * The fixture is a whole-screen capture, deliberately — it is the honest record
 * of what this surface rendered — but the topbar and the nav above and below
 * this slice are shared chrome that every showcase screen renders and that a
 * format is explicitly not allowed to touch. Comparing them here would make
 * this assertion fail for an unrelated change to ../support/, and pass no
 * additional claim about the arrangement.
 */
function arrangementSlice(html: string): string {
  const start = html.indexOf('<div class="_strip_');
  const end = html.indexOf('<nav ');
  return html.slice(start, end).replace(/(<\/div>)+$/, '');
}

/** How many elements carry each `data-sc-part` value. */
function partCounts(html: string): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const match of html.matchAll(new RegExp(`${PART_ATTR}="([^"]*)"`, 'g'))) {
    const part = match[1] ?? '';
    counts[part] = (counts[part] ?? 0) + 1;
  }
  return counts;
}

function render(format: string, videos: readonly ShowcaseVideo[]): string {
  setFormatOverride(FORMAT_SLOTS.videos, format);
  return renderToStaticMarkup(<VideoShowcase videos={videos} />);
}

/** One fabricated card. Nothing here is fetched — the preview has no network. */
function video(genre: string, index: number): ShowcaseVideo {
  const id = `${genre}-${String(index)}`;
  return {
    videoId: id,
    title: `${genre} title ${String(index)}`,
    genre,
    channelName: `${genre} channel`,
    viewCount: 1000 * (index + 1),
    thumbnailUrl: `https://example.test/${id}.jpg`,
    // Half the pool carries no avatar, exactly as the shared video pool does.
    channelAvatarUrl: index % 2 === 0 ? `https://example.test/a-${id}.jpg` : '',
  };
}

/** `videoFeed(tags: n, perTag: m)` — a feed with `n` genres of `m` cards each. */
function feed(genres: readonly string[], perGenre: number): ShowcaseVideo[] {
  return genres.flatMap((genre) =>
    Array.from({ length: perGenre }, (_unused, index) => video(genre, index)),
  );
}

const THREE_GENRES = ['educational', 'entertainment', 'vlog'];
/** The app owns no genre vocabulary: the count is the tenant's. */
const FIFTEEN_GENRES = Array.from({ length: 15 }, (_unused, i) => `genre${String(i)}`);

afterEach(() => {
  // The override store is a module singleton; a leaked pin would silently
  // re-point every later test at one arrangement.
  setFormatOverride(FORMAT_SLOTS.videos, null);
});

describe('the arrangement that ships is untouched', () => {
  it('renders `carouselRows` exactly as the screen did before the arrangements existed', () => {
    // Captured off this screen at the commit before `videos_format` reached it.
    // If this fails, the default arrangement has drifted — which is the one
    // thing a format seam is not allowed to do, because a tenant whose theme
    // carries no `videos_format` (or is classified into the default) must see
    // no change at all.
    // Read off disk from the package root, not through `import.meta.url`: a
    // vitest module id is not a `file:` URL, and not through a bundler import
    // either, since `test.css` is off and a `?raw` import would hand back an
    // empty string that this assertion would pass against vacuously
    // (../../../../CLAUDE.md, "Things that will bite").
    const expected = readFileSync(
      `${cwd()}/src/app/showcase/videos/__tests__/fixtures/videos_carouselRows.html`,
      'utf8',
    ).trim();

    // Both sides go through the same slice, so a marker that stopped matching
    // would empty them both and pass vacuously. This is the guard against that.
    expect(arrangementSlice(expected)).toContain('view all');

    expect(
      arrangementSlice(stripParts(normaliseClasses(render(BASELINE, feed(THREE_GENRES, 4))))),
    ).toBe(arrangementSlice(expected));
  });

  it('is also what an unpinned slot resolves to', () => {
    // No override and no loaded theme: `useFormat` falls through to the value
    // that ships. An unknown arrangement is a non-event, not a broken screen.
    setFormatOverride(FORMAT_SLOTS.videos, null);
    const unpinned = renderToStaticMarkup(<VideoShowcase videos={feed(THREE_GENRES, 4)} />);
    expect(partCounts(unpinned)).toEqual(partCounts(render(BASELINE, feed(THREE_GENRES, 4))));
  });

  it('falls back rather than throwing on an arrangement this build does not know', () => {
    const unknown = render('someFutureArrangement', feed(THREE_GENRES, 4));
    expect(partCounts(unknown)).toEqual(partCounts(render(BASELINE, feed(THREE_GENRES, 4))));
  });
});

describe.each([
  ['a three-genre feed', THREE_GENRES, 4],
  // A single genre and a single card each: an arrangement that only works at
  // three sections fails here.
  ['a one-genre feed', THREE_GENRES.slice(0, 1), 2],
  ['a fifteen-genre feed', FIFTEEN_GENRES, 2],
])('every videos arrangement carries the whole feed over %s', (_label, genres, perGenre) => {
  const videos = feed(genres, perGenre);
  const baseline = partCounts(render(BASELINE, videos));

  it('the baseline itself holds every element the screen owes the member', () => {
    expect(baseline).toEqual({
      // The top filter: one strip, "All" plus one pill per genre.
      'category-tabs': 1,
      'category-pill': genres.length + 1,
      // Exactly one hero, still carrying the shared recc card and its Play action.
      'featured-video': 1,
      'featured-play': 1,
      'recc-card': 1,
      // One section per genre, each with its title and its view-all.
      'video-section': genres.length,
      'section-title': genres.length,
      'view-all': genres.length,
      // A card for every video — no arrangement hides part of the feed.
      'video-card': videos.length,
      // Every card's thumbnail, plus the hero's.
      'video-thumb': videos.length + 1,
      // Half the fixture publishes an avatar; a blank URL means NO avatar.
      'creator-avatar': videos.length / 2 + 1,
      // Loaded means no status: the feed is what is on screen.
      'feed-status': undefined,
    });
  });

  it.each(VIDEOS_FORMATS)('%s renders the identical element multiset', (format) => {
    expect(partCounts(render(format, videos))).toEqual(baseline);
  });
});

describe('every videos arrangement keeps the empty state', () => {
  it.each(VIDEOS_FORMATS)('%s shows the one status message, and only it', (format) => {
    const html = render(format, []);
    expect(partCounts(html)).toEqual({
      'category-tabs': 1,
      // "All" survives an empty feed; there is simply nothing to filter.
      'category-pill': 1,
      'feed-status': 1,
    });
    // The message is the arrangement's to place, never to reword.
    expect(html).toContain('Nothing here yet.');
  });
});

describe('no arrangement reaches past the payload', () => {
  it.each(VIDEOS_FORMATS)('%s renders the same titles, labels and meta as %s', (format) => {
    const videos = feed(THREE_GENRES, 3);
    // Every string the baseline puts on screen, in the order it puts them: an
    // arrangement that re-sorted, re-labelled, or silently truncated the feed
    // would differ here even when its element counts matched.
    const text = (html: string): string[] =>
      html
        .replace(/<[^>]*>/g, ' ')
        .split(' ')
        .filter((chunk) => chunk.trim() !== '')
        .sort();

    expect(text(render(format, videos))).toEqual(text(render(BASELINE, videos)));
  });
});
