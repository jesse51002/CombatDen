// The functional-equivalence gate for `rank_format`, and the React mirror of
// `MobileApp/test/rank_invariants_test.dart`.
//
// A layout format may change ARRANGEMENT ONLY. This asserts it mechanically:
// every value of the vocabulary is rendered as the real screen and its part
// multiset is compared against the contract below. A layout that drops the
// range selector, loses the progress label, or quietly shows the celebration
// hero twice fails here rather than in review. It is the check that makes the
// "no feature added, none removed" claim verifiable instead of argued — which
// is the claim the whole layout-format idea is sold on.
//
// WHY `data-rank-part` AND NOT CLASS NAMES: a Flutter widget carries its own
// type into the tree and `find.byType` reads it; a DOM node carries nothing,
// and a `.module.css` import returns `''` under vitest, so every class-based
// query would pass vacuously against nothing (../../../../CLAUDE.md, "Things
// that will bite"). ../rankParts.ts is the stand-in.
//
// AND `sparkleStack` IS PINNED TO WHAT SHIPS. The multiset check alone would
// pass for a `sparkleStack` that had been quietly restyled while the other four
// were written, so the last group snapshots its structure specifically: a
// tenant with no layout slot must see the screen it saw before this vocabulary
// existed.

import { act } from 'react';
import type { Root } from 'react-dom/client';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';

import { RANK_FORMATS, setFormatOverride, FORMAT_SLOTS } from '../../formats';
import type { RankFormat } from '../../formats';
import type { ShowcaseVideo } from '../../showcaseContent';

import { ProfileShowcase } from '../ProfileShowcase';
import { RANK_PART } from '../rankParts';
import type { RankPart } from '../rankParts';
import { SHOWCASE_RANK } from '../mockRankProgress';

/**
 * Two educational cards so the level-up carousel actually renders. It hides
 * itself on an empty feed (and takes its divider with it), so an empty list
 * would make "the section is present" vacuous in every arrangement at once.
 */
const VIDEOS: readonly ShowcaseVideo[] = Object.freeze([
  videoFixture('a', 'educational'),
  videoFixture('b', 'educational'),
  // One outside the bucket, so the narrowing is exercised rather than assumed.
  videoFixture('c', 'entertainment'),
]);

function videoFixture(id: string, genre: string): ShowcaseVideo {
  return {
    videoId: id,
    title: `Video ${id}`,
    channelName: 'Combat Culture',
    thumbnailUrl: `https://example.invalid/${id}.jpg`,
    channelAvatarUrl: '',
    viewCount: 1000,
    genre,
  };
}

/** How many of each part the screen carries, in EVERY arrangement. */
const CONTRACT: Readonly<Record<RankPart, number>> = Object.freeze({
  // The chrome the screen sits in.
  [RANK_PART.topbar]: 1,
  // The celebration signature: present, and rationed to ONE. A layout may move
  // it or overlay it; none may multiply it.
  [RANK_PART.streakHero]: 1,
  // The CURRENT rank, and its belt.
  [RANK_PART.rankHeader]: 1,
  [RANK_PART.rankBelt]: 1,
  // Progress over time, and the range it is scoped to.
  [RANK_PART.ratingGraph]: 1,
  [RANK_PART.timeframePill]: 4,
  // The NEXT rank: all four elements, wherever they landed.
  [RANK_PART.nextRankBadge]: 1,
  [RANK_PART.nextRankTitle]: 1,
  [RANK_PART.nextRankProgress]: 1,
  [RANK_PART.nextRankProgressLabel]: 1,
  // The videos that feed the loop back into content.
  [RANK_PART.levelUpVideos]: 1,
});

// React only treats `act` as real when this flag is on, and warns on every
// render without it. The package's shared setup file lives under `src/lib/`,
// which is the runtime a consumer installs — a React-DOM testing flag has no
// business in there, so it is set beside the only tests that need it.
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let mounted: { host: HTMLDivElement; root: Root } | null = null;

function render(format: RankFormat): HTMLDivElement {
  // The preview's own override store is how the dev picker forces a value, so
  // the gate drives the screen exactly the way a reviewer does — Dart's
  // `formatOverride`, without a second code path to keep honest.
  setFormatOverride(FORMAT_SLOTS.rank, format);
  const host = document.createElement('div');
  document.body.append(host);
  const root = createRoot(host);
  act(() => {
    root.render(<ProfileShowcase videos={VIDEOS} />);
  });
  mounted = { host, root };
  return host;
}

afterEach(() => {
  // UNMOUNT FIRST, then release the override. The override store is a module
  // singleton that notifies its subscribers, so clearing it while the screen is
  // still mounted schedules a React update from outside `act` — the exact thing
  // the act environment exists to catch.
  const current = mounted;
  mounted = null;
  if (current !== null) {
    act(() => {
      current.root.unmount();
    });
    current.host.remove();
  }
  setFormatOverride(FORMAT_SLOTS.rank, null);
});

function countParts(host: HTMLElement): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const node of host.querySelectorAll('[data-rank-part]')) {
    const part = node.getAttribute('data-rank-part') ?? '';
    counts[part] = (counts[part] ?? 0) + 1;
  }
  return counts;
}

/** The visible words of the subtree, whitespace-collapsed. */
function text(host: HTMLElement): string {
  return (host.textContent ?? '').replace(/\s+/g, ' ').trim();
}

describe('every rank format carries every element of the screen', () => {
  for (const format of RANK_FORMATS) {
    it(format, () => {
      const host = render(format);

      // The multiset itself — the whole invariant in one comparison.
      expect(countParts(host)).toEqual(CONTRACT);

      // The CURRENT rank, with both its names.
      expect(text(host)).toContain(SHOWCASE_RANK.name);
      expect(text(host)).toContain(SHOWCASE_RANK.subLabel ?? '');

      // The progress label is the only place the screen says what the progress
      // counts, so it is asserted verbatim: a layout that truncated it to fit
      // would be dropping information, not rearranging it.
      expect(text(host)).toContain('17 / 24 classes');

      // The range chips are the same four in every layout, and exactly one of
      // them reads as active.
      expect([...host.querySelectorAll('[data-rank-part="timeframePill"]')].map(
        (node) => node.textContent,
      )).toEqual(['1W', '1M', '1Y', 'ALL']);
      expect(host.querySelectorAll('[data-rank-active]')).toHaveLength(1);
    });
  }
});

describe('every rank format keeps the two belts', () => {
  // Only the CURRENT rank and the NEXT one are available. An arrangement
  // implying rank HISTORY would need a series this screen never fetches. This
  // pins the other direction too: `next_rank_belt_image` is generated for every
  // theme and Profile is its ONLY consumer, so an arrangement that dropped it
  // would take the tenth generated image per theme back off the screen.
  for (const format of RANK_FORMATS) {
    it(format, () => {
      const host = render(format);
      const sources = [...host.querySelectorAll('img')].map((img) => img.getAttribute('src') ?? '');
      expect(sources.filter((src) => src.includes('profile_rank_belt_gold'))).toHaveLength(1);
      expect(sources.filter((src) => src.includes('profile_next_rank_belt'))).toHaveLength(1);
    });
  }
});

describe('every rank format keeps all four nav destinations', () => {
  for (const format of RANK_FORMATS) {
    it(format, () => {
      const host = render(format);
      const nav = host.querySelector('nav');
      expect(nav).not.toBeNull();
      for (const label of ['Home', 'Rank', 'Reward', 'Videos']) {
        expect(text(nav as HTMLElement)).toContain(label);
      }
    });
  }
});

describe('sparkleStack is unchanged from what ships', () => {
  // The multiset above cannot catch a `sparkleStack` that was quietly restyled
  // while the other four were being written, because a restyle keeps every
  // part. This pins its STRUCTURE: the order the blocks appear in, and the
  // shipped treatment of each element that has more than one.
  it('renders the shipped block order', () => {
    const host = render('sparkleStack');
    const order = [...host.querySelectorAll('[data-rank-part]')].map((node) =>
      node.getAttribute('data-rank-part'),
    );
    expect(order).toEqual([
      RANK_PART.topbar,
      RANK_PART.streakHero,
      RANK_PART.rankHeader,
      RANK_PART.rankBelt,
      RANK_PART.ratingGraph,
      RANK_PART.timeframePill,
      RANK_PART.timeframePill,
      RANK_PART.timeframePill,
      RANK_PART.timeframePill,
      RANK_PART.nextRankTitle,
      RANK_PART.nextRankProgressLabel,
      RANK_PART.nextRankProgress,
      RANK_PART.nextRankBadge,
      RANK_PART.levelUpVideos,
    ]);
  });

  it('keeps the shipped treatments: 100pt ring badge, md plot, loose pill row', () => {
    const host = render('sparkleStack');

    // The ring hugging a 100pt badge — `_kBadgeShipped` with `buttonBorderSize`.
    const badge = host.querySelector<HTMLElement>('[data-rank-part="nextRankBadge"]');
    expect(badge?.style.getPropertyValue('--nr-badge-size')).toBe('100px');
    const ring = host.querySelector('[data-rank-part="nextRankProgress"] svg');
    expect(ring?.getAttribute('viewBox')).toBe('0 0 100 100');

    // The shipped plot box, 393 x 196.5, inside the standard gutter.
    const plot = host.querySelector<HTMLElement>('[data-rank-part="ratingGraph"]');
    expect(plot?.style.aspectRatio).toBe('393 / 196.5');
    expect(plot?.querySelector('svg')?.getAttribute('viewBox')).toBe('0 0 393 196.5');

    // The axis is still bracketed by the classes the member needs.
    expect(text(plot as HTMLElement)).toBe(`${String(SHOWCASE_RANK.classesTillNextStep)}0`);
  });
});
