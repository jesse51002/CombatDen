// The functional-equivalence gate for `class_format`, porting
// `MobileApp/test/class_invariants_test.dart` group for group.
//
// An arrangement may change ARRANGEMENT ONLY: no screen merged or split, no
// functionality added, none removed, and no variant reaching data the shipped
// screen did not already have. That is a correctness property rather than a
// style note — it is what makes the whole idea sellable, because the app a
// member gets is rearranged, never reduced.
//
// HOW A COMPONENT IS COUNTED. Dart counts widget TYPES with `find.byType`,
// because a widget carries its type into the element tree. A DOM node carries
// no such thing, and CSS-module class names are unusable here (`test.css`
// defaults to false under vitest, so a `.module.css` import returns `''` and
// every class-based query passes vacuously — ../../../CLAUDE.md). So each part
// stamps `data-class-part` and this file counts those, exactly as
// ./videosFormats.test.tsx and ../profile/rankParts.ts do for their screens.
//
// `skipOffstage: false` IS THE LOAD-BEARING DETAIL, and it ports directly.
// The Dart counts through the WHOLE tree so a section parked behind a tab still
// counts and a duplicate parked there still fails. `renderToStaticMarkup`
// serialises the whole tree for the same reason: `sectionTabs` renders all
// three panes always and hides two with the `hidden` ATTRIBUTE rather than
// unmounting them, so they are in the markup and in the count. A React version
// that only counted VISIBLE nodes would pass while a duplicate hid behind a
// tab, which is precisely the bug the Dart comment calls out.
//
// THE SWIPE GROUP IS THE ONE ADAPTATION, and it is flagged rather than quiet.
// Dart asserts a horizontal-drag count of 1, rising to 2 only for
// `sectionTabs`. The screen-level one of those two navigates into the
// post-class flow (`Navigator.pushReplacementNamed`) — this browser has no
// router, and the slideshow's own next-screen arrows live in ../../browser/,
// which this island may not import (Gate 2a). Porting it as a handler with no
// destination would invent a dead affordance, so it is absent and the count
// below is 1 for `sectionTabs` and 0 elsewhere: the same CONTRACT (the tab
// swipe is `sectionTabs`'s own extra), minus a hook that has no counterpart.
// See ../classdetail/ClassDetailShowcase.tsx.

import { readFileSync } from 'node:fs';
import { cwd } from 'node:process';

import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, describe, expect, it } from 'vitest';

import { detailFor, previewClassCard } from '../classdetail/classDetail';
import { ClassDetailShowcase } from '../classdetail/ClassDetailShowcase';
import { CLASS_PART, PART_ATTR } from '../classdetail/classParts';
import { CLASS_FORMATS, FORMAT_SLOTS, setFormatOverride } from '../formats';
import type { ShowcaseClassInfo } from '../showcaseContent';

// React only suppresses its "not configured to support act(...)" warning when
// the flag is set; vitest sets no such default.
(globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

/** The arrangement that ships, and the baseline every other is diffed against. */
const BASELINE = CLASS_FORMATS[0];

const GYM_NAME = 'Your Gym';

/**
 * The sample, mirroring `class_invariants_test.dart`'s `_sample`. Nothing here
 * is fetched — the preview has no network — and the class name is the string
 * the "data reaches the meta" assertion looks for.
 */
const SAMPLE: ShowcaseClassInfo = {
  name: 'Muay Thai Sparring',
  imageUrl: 'https://example.test/class.jpg',
  instructorName: 'Coach Ana',
  description: 'Six rounds on the pads, then live rounds with the team.',
  instructorBio: 'Ten years cornering fighters at the national level.',
  instructorImageUrl: 'https://example.test/coach.jpg',
};

const CLASSES: readonly ShowcaseClassInfo[] = [SAMPLE];

function render(format: string): string {
  setFormatOverride(FORMAT_SLOTS.class, format);
  return renderToStaticMarkup(<ClassDetailShowcase gymName={GYM_NAME} classes={CLASSES} />);
}

/** How many elements carry each `data-class-part` value. */
function partCounts(html: string): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const match of html.matchAll(new RegExp(`${PART_ATTR}="([^"]*)"`, 'g'))) {
    const part = match[1] ?? '';
    counts[part] = (counts[part] ?? 0) + 1;
  }
  return counts;
}

/**
 * A CSS-module class arrives as `_local_ab12cd`, and the six-hex tail is a hash
 * of the FILE — so moving a rule between stylesheets changes it while changing
 * nothing about the rendered page. Normalised away; the local name, which does
 * carry intent, is kept.
 */
function normaliseClasses(html: string): string {
  return html.replace(/(_[A-Za-z0-9]+)_[0-9a-f]{6}/g, '$1_');
}

/** `data-class-part` is instrumentation; it is not markup the screen shipped. */
function stripParts(html: string): string {
  return html.replace(new RegExp(` ${PART_ATTR}="[^"]*"`, 'g'), '');
}

/** Every visible word, sorted — what the screen actually says. */
function text(html: string): string[] {
  return html
    .replace(/<[^>]*>/g, ' ')
    .split(/\s+/)
    .filter((chunk) => chunk.trim() !== '')
    .sort();
}

afterEach(() => {
  // The override store is a module singleton; a leaked pin would silently
  // re-point every later test at one arrangement.
  setFormatOverride(FORMAT_SLOTS.class, null);
});

describe('the arrangement that ships is untouched', () => {
  it('renders `bannerStack` exactly as the committed baseline', () => {
    // UNLIKE ./videosFormats.test.tsx's fixture, this one is NOT a capture from
    // before the formats existed — this screen had no "before" in this package,
    // because `class_format` is the slot whose surface had never been built
    // here at all. It is a lock going FORWARD: the default arrangement is what
    // a tenant sees when their theme carries no `class_format` (or classifies
    // into the default), so work on the other four must never drift it. Any
    // deliberate change to `bannerStack` re-captures this file in the same
    // commit, which is what makes the drift visible in review.
    //
    // Read off disk from the package root, not through a bundler import: with
    // `test.css` off, a `?raw` import hands back an empty string that this
    // assertion would pass against vacuously (../../../CLAUDE.md).
    const expected = readFileSync(
      `${cwd()}/src/app/showcase/__tests__/fixtures/class_bannerStack.html`,
      'utf8',
    ).trim();

    expect(stripParts(normaliseClasses(render(BASELINE)))).toBe(expected);
  });

  it('is also what an unpinned slot resolves to', () => {
    // No override and no loaded theme: `useFormat` falls through to the value
    // that ships.
    setFormatOverride(FORMAT_SLOTS.class, null);
    const unpinned = renderToStaticMarkup(
      <ClassDetailShowcase gymName={GYM_NAME} classes={CLASSES} />,
    );
    expect(partCounts(unpinned)).toEqual(partCounts(render(BASELINE)));
  });

  it('falls back rather than throwing on an arrangement this build does not know', () => {
    // The vocabulary lives in the app's `app.yaml` and this build may simply be
    // older than it. That degradation is the whole reason an unknown
    // arrangement is a non-event instead of a broken screen.
    expect(partCounts(render('someFutureArrangement'))).toEqual(partCounts(render(BASELINE)));
  });
});

describe('every class format carries every element of the screen', () => {
  // `expectExactlyOne` for each, ported one for one from the Dart group.
  const EXPECTED: Record<string, number> = {
    // The chrome, with the only way off the screen that does not commit.
    [CLASS_PART.topbar]: 1,
    [CLASS_PART.back]: 1,
    // The photo is never dropped — `specBrief` shrinks it to a thumb, which is
    // still one banner.
    [CLASS_PART.banner]: 1,
    // The four content sections.
    [CLASS_PART.meta]: 1,
    [CLASS_PART.details]: 1,
    [CLASS_PART.instructor]: 1,
    [CLASS_PART.location]: 1,
    // The one commit point, counted at the footer AND at the button: a layout
    // that repeats the CTA outside the footer is caught by the second.
    [CLASS_PART.reserve]: 1,
    [CLASS_PART.reserveButton]: 1,
  };

  it.each(CLASS_FORMATS)('%s renders the identical element multiset', (format) => {
    expect(partCounts(render(format))).toEqual(EXPECTED);
  });

  it.each(CLASS_FORMATS)('%s puts the class name on screen', (format) => {
    // The data the screen was handed actually reaches the meta.
    expect(render(format)).toContain(SAMPLE.name);
  });
});

describe('every class format has exactly ONE reserve action', () => {
  it.each(CLASS_FORMATS)('%s shows the one commit point, never parked', (format) => {
    const html = render(format);
    expect(partCounts(html)[CLASS_PART.reserveButton]).toBe(1);
    // And it is the theme's `reserve_cta` text, degrading to the shipped label.
    expect(html).toContain('Reserve your spot');
  });
});

describe('no class format drops or truncates the payload', () => {
  // Every DATUM the screen was handed, derived from the payload rather than
  // retyped, so a change to the demo content cannot leave this asserting
  // yesterday's strings.
  const detail = detailFor(previewClassCard(CLASSES), GYM_NAME);
  const cls = detail.classData;
  const DATA: readonly string[] = [
    cls.name,
    cls.timeRange,
    cls.description,
    cls.instructorBio,
    detail.location,
    detail.dateLabel,
    detail.address,
    `${String(cls.attending ?? 0)} attending`,
  ];

  it.each(CLASS_FORMATS)('%s shows every datum the baseline shows', (format) => {
    // The element counts above prove no SECTION was dropped; this proves no
    // section was emptied. An arrangement that rendered the instructor block
    // but truncated the bio, or moved the address off screen, fails here with
    // a matching element multiset.
    const html = render(format);
    for (const datum of DATA) expect(html).toContain(datum);
  });

  it.each(CLASS_FORMATS)('%s introduces no prose the baseline does not have', (format) => {
    // The other direction: a variant may not reach data the shipped screen did
    // not already have. Compared against the baseline's own words PLUS the
    // arrangement-owned LABELS, which are chrome rather than data — the tab
    // names `sectionTabs` puts on its selector and the row labels `specBrief`
    // puts down its spec table. Both are in the Dart too
    // (`ClassTabBar(labels: [...])`, `_SpecRow(label: ...)`), and neither is a
    // fact about the class; they are how that arrangement points at facts the
    // baseline reaches by scrolling.
    const allowed = new Set([...text(render(BASELINE)), 'Date', 'Time', 'Attending']);
    for (const word of text(render(format))) expect(allowed).toContain(word);
  });
});

describe('sectionTabs parks its sections without dropping them', () => {
  const TABS = ['Details', 'Instructor', 'Location'];

  it('renders all three panes at once, two of them hidden', () => {
    // The `IndexedStack`-not-`PageView` property, which is the whole reason
    // `sectionTabs` is an arrangement rather than a different screen: a pager
    // never builds the pages you have not visited, which would take two of this
    // screen's sections OUT OF THE TREE. Hiding a section behind a tab is an
    // arrangement; dropping it is a different screen.
    const html = render('sectionTabs');
    expect(html.match(/role="tabpanel"/g)).toHaveLength(3);
    expect(html.match(/hidden=""/g)).toHaveLength(2);
  });

  it.each(TABS.map((label, index) => [label, index] as const))(
    'the %s tab reveals its own section',
    (label, index) => {
      // The one arrangement that hides content behind a tap has to prove the
      // tap reaches it: the sections it parks are reachable, not orphaned.
      setFormatOverride(FORMAT_SLOTS.class, 'sectionTabs');
      const host = document.createElement('div');
      document.body.appendChild(host);
      const root = createRoot(host);
      act(() => {
        root.render(<ClassDetailShowcase gymName={GYM_NAME} classes={CLASSES} />);
      });

      const tab = [...host.querySelectorAll('[role="tab"]')].find(
        (node) => node.textContent === label,
      );
      expect(tab).toBeDefined();
      act(() => {
        (tab as HTMLElement).click();
      });

      const panes = [...host.querySelectorAll('[role="tabpanel"]')];
      expect(panes).toHaveLength(3);
      // Exactly the tapped pane is showing, and every other stays in the tree.
      panes.forEach((pane, i) => {
        expect((pane as HTMLElement).hidden).toBe(i !== index);
      });

      act(() => {
        root.unmount();
      });
      host.remove();
    },
  );
});

describe('the horizontal swipe belongs to sectionTabs alone', () => {
  // Dart asserts 1 drag surface, rising to 2 for `sectionTabs`. The
  // screen-level one has no counterpart in a preview with no router (see this
  // file's header), so the ported contract is 1 for `sectionTabs` and 0
  // elsewhere — the tab swipe is still that arrangement's own affordance, and
  // still the only one.
  it.each(CLASS_FORMATS)('%s carries the expected number of swipe surfaces', (format) => {
    const swipes = render(format).match(/data-class-swipe="/g) ?? [];
    expect(swipes).toHaveLength(format === 'sectionTabs' ? 1 : 0);
  });
});
