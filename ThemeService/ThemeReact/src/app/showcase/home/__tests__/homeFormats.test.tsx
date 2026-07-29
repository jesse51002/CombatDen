// THE FUNCTIONAL-EQUIVALENCE GATE FOR `home_format`.
//
// Ports MobileApp/test/home_invariants_test.dart, and it is a gate rather than
// a smoke test for the same reason: a layout format may change ARRANGEMENT
// ONLY. No screen merged or split, no functionality added, none removed, and no
// variant reaching data the shipped screen did not already have. Dart proves
// that by diffing each variant's component multiset against the baseline; this
// does the same thing against the DOM.
//
// TWO ASSERTIONS, and they answer two different questions.
//
//   1. EVERY VALUE RENDERS THE SAME THINGS. One signature per arrangement (day
//      groups, rows, thumbnails, time blocks, date pills, nav items, and the
//      multiset of every class name / instructor / attendee line on the board),
//      compared against `agendaList`'s. A generated arrangement that drops a
//      thumbnail, loses a day, or quietly stops rendering the instructor fails
//      here rather than in review.
//
//      Rows and time blocks are COUNTED, not text-matched, because `timeSpine`
//      re-formats the time on purpose (`9:00am` over `55 min` in its gutter
//      instead of `9:00am - 9:55am (55 min)` inline) — the time MOVES, which is
//      an arrangement; rendering it twice or not at all would not be. That is
//      exactly why <ClassItemTime> is one component: counting it is what proves
//      it is rendered once per row in every value.
//
//   2. `agendaList` IS UNCHANGED FROM WHAT SHIPS. ./agendaListBaseline.html is
//      the rendered DOM captured from the flat pre-format home body, with the
//      CSS-module hash suffixes normalised away (`_row_ea9f53` -> `row`) so a
//      class that moved to another stylesheet still compares equal. Element for
//      element, attribute for attribute, text for text. Re-capture it ONLY when
//      the shipped arrangement is meant to change.
//
//      IT IS THE SCHEDULE BODY, NOT THE SCREEN. The topbar and the bottom nav
//      are the tenant's `app_shell_format` — a different slot, arranged by
//      different code — so a legitimate change over there must not redden the
//      home gate with a false "you changed the shipped screen". The fixture
//      therefore starts at the date rail, and the chrome is covered instead by
//      the signature above, which compares the five arrangements against each
//      other inside one render and so is indifferent to what the shell does.
//
// The clock is frozen because the board's day labels are relative ("Today",
// "Sat 17"); only `Date` is faked, never the timers React schedules on.

import { readFileSync } from 'node:fs';
import { cwd } from 'node:process';

import type { ReactElement } from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import type { Root } from 'react-dom/client';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

import { HOME_FORMATS } from '../../formats';
import type { HomeFormat } from '../../formats';
import type { ShowcaseClassInfo } from '../../showcaseContent';
import { ShowcaseBottomNav } from '../../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../../support/ShowcaseScaffold';
import { ShowcaseTopbar } from '../../support/ShowcaseTopbar';
import metaStyles from '../classItem/ClassItemMeta.module.css';
import timeStyles from '../classItem/ClassItemTime.module.css';
import dateRowStyles from '../DateRow.module.css';
import dateTabStyles from '../DateTab.module.css';
import dayGroupStyles from '../DayClassGroup.module.css';
import { HomeLayoutBody } from '../HomeLayoutBody';
import { HomeShowcase } from '../HomeShowcase';
import scheduleStyles from '../layouts/HomeScheduleScroll.module.css';

/**
 * The gym's classes, fixed so the schedule the generator derives from them is
 * identical on every run. Four of them, because the generator rotates classes
 * through four fixed time slots. Dart's `kTestClasses`.
 */
const TEST_CLASSES: readonly ShowcaseClassInfo[] = Object.freeze([
  {
    name: 'Muay Thai',
    imageUrl: 'https://layout.test/muay-thai.jpg',
    instructorName: 'Andy Zerger',
  },
  { name: 'BJJ No-Gi', imageUrl: 'https://layout.test/bjj.jpg', instructorName: 'Renata Alves' },
  {
    name: 'Boxing Basics',
    imageUrl: 'https://layout.test/boxing.jpg',
    instructorName: 'Marcus Hale',
  },
  {
    name: 'Wrestling',
    imageUrl: 'https://layout.test/wrestling.jpg',
    instructorName: 'Dana Whitfield',
  },
]);

/** The board's window (`VISIBLE_DAYS`) and the four classes in each day. */
const DAYS = 5;
const ROWS = DAYS * TEST_CLASSES.length;

/**
 * Read off disk against the CWD, exactly as ../../../__tests__/tokens.test.ts
 * reads its stylesheet: `import.meta.url` is Vite's transformed `/src/...` URL
 * under vitest, not a `file:` one, and importing the fixture would hand back
 * `''` for the same reason a `.css` import does.
 */
const BASELINE = readFileSync(
  `${cwd()}/src/app/showcase/home/__tests__/agendaListBaseline.html`,
  'utf8',
).trimEnd();

/**
 * `_<key>_<filehash>` -> `<key>`. The suffix is a hash of the STYLESHEET, so
 * moving a rule to another file changes it while the element is untouched —
 * normalising it is what lets the baseline survive the split into ../classItem/
 * without weakening into a class-blind comparison.
 */
function normalizeClassHashes(html: string): string {
  return html.replace(/_([A-Za-z0-9]+)_[0-9a-f]{6}/g, '$1');
}

/**
 * The schedule body with the topbar dropped — everything `home_format`
 * arranges, and nothing `app_shell_format` does. See the header.
 */
function scheduleBody(el: HTMLElement): string {
  const body = el.querySelector(`.${scheduleStyles.body}`);
  if (body === null) throw new Error('no schedule body rendered');
  const clone = body.cloneNode(true) as HTMLElement;
  clone.firstElementChild?.remove();
  return normalizeClassHashes(clone.innerHTML);
}

let host: HTMLDivElement | null = null;
let root: Root | null = null;

function render(node: ReactElement): HTMLDivElement {
  const mounted = document.createElement('div');
  document.body.appendChild(mounted);
  const created = createRoot(mounted);
  act(() => {
    created.render(node);
  });
  host = mounted;
  root = created;
  return mounted;
}

function unmount(): void {
  const created = root;
  if (created !== null) {
    act(() => {
      created.unmount();
    });
  }
  host?.remove();
  root = null;
  host = null;
}

/** The whole screen with the arrangement forced — Dart's `formatOverride`. */
function renderHome(format: HomeFormat): HTMLDivElement {
  return render(
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll
      bottomNav={<ShowcaseBottomNav selected="home" />}
    >
      <HomeLayoutBody
        format={format}
        classes={TEST_CLASSES}
        topbar={
          <ShowcaseTopbar
            mode="bigLogo"
            gymName="Your Gym"
            streakDays={3}
            pointsLabel="3.4k"
            rankBadgeAsset="icon_rank_belt.png"
            themeTabPreview
          />
        }
      />
    </ShowcaseScaffold>,
  );
}

function count(el: HTMLElement, selector: string): number {
  return el.querySelectorAll(selector).length;
}

function texts(el: HTMLElement, selector: string): readonly string[] {
  return [...el.querySelectorAll(selector)].map((node) => node.textContent ?? '').sort();
}

interface Signature {
  readonly dayGroups: number;
  readonly dayLabels: readonly string[];
  readonly rows: number;
  readonly classNames: readonly string[];
  readonly instructors: readonly string[];
  readonly attendeeLines: readonly string[];
  readonly bookedMarks: number;
  readonly times: number;
  readonly thumbnails: number;
  readonly dateRails: number;
  readonly datePills: number;
  readonly selectedPills: number;
  readonly navItems: number;
}

/**
 * The element set the screen renders, as one comparable value — the DOM
 * analogue of Dart's component multiset. Scoped to the schedule board and its
 * chrome, which is what `expectClassRowComplete` and the `expect`s around it
 * cover there.
 */
function signature(el: HTMLElement): Signature {
  return {
    dayGroups: count(el, `.${dayGroupStyles.group}`),
    dayLabels: texts(el, `.${dayGroupStyles.label}`),
    // One meta column per class row, whatever treatment drew it.
    rows: count(el, `.${metaStyles.name}`),
    classNames: texts(el, `.${metaStyles.name}`),
    instructors: texts(el, `.${metaStyles.mentor}`),
    attendeeLines: texts(el, `.${metaStyles.attending}`),
    // The booked mark rides home's BOOKED page, which this preview does not
    // have — so it is absent in every arrangement, and no format may add it.
    bookedMarks: count(el, `.${metaStyles.booked}`),
    // The time is rendered exactly once per row: inline, or hoisted into the
    // spine's gutter. Counted, never text-matched — see the header.
    times: count(el, `.${timeStyles.meta}`) + count(el, `.${timeStyles.stacked}`),
    // Every treatment renders exactly one image per row.
    thumbnails: count(el, `.${dayGroupStyles.group} img`),
    dateRails: count(el, `.${dateRowStyles.dateStrip}`),
    datePills: count(el, `.${dateTabStyles.tab}`),
    selectedPills: count(el, `.${dateTabStyles.selected}`),
    navItems: count(el, 'nav > *'),
  };
}

describe('home formats', () => {
  const signatures = new Map<HomeFormat, Signature>();

  beforeAll(() => {
    (globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT =
      true;
    // Only `Date`: the board's day labels are relative, and faking the timers
    // React schedules on would deadlock `act`.
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(2026, 0, 15, 9, 0, 0));
    for (const format of HOME_FORMATS) {
      signatures.set(format, signature(renderHome(format)));
      unmount();
    }
  });

  afterAll(() => {
    vi.useRealTimers();
  });

  afterEach(unmount);

  it('arranges every value in the wire vocabulary', () => {
    // The vocabulary IS the wire. A value the switch does not handle would be a
    // blank screen for whatever tenant the classifier picked it for, so this is
    // what catches a value added to ../../formats.ts and never arranged.
    expect(HOME_FORMATS).toHaveLength(5);
    expect([...signatures.keys()]).toEqual([...HOME_FORMATS]);
  });

  it('renders the whole board in the baseline, not an empty one', () => {
    // Guards the comparison below: five identical EMPTY screens would pass a
    // pure equality check and prove nothing.
    expect(signatures.get('agendaList')).toMatchObject({
      dayGroups: DAYS,
      rows: ROWS,
      times: ROWS,
      thumbnails: ROWS,
      dateRails: 1,
      datePills: DAYS,
      selectedPills: 1,
      bookedMarks: 0,
      navItems: 4,
    });
    expect(signatures.get('agendaList')?.classNames).toHaveLength(ROWS);
    expect(signatures.get('agendaList')?.instructors).toHaveLength(ROWS);
    expect(signatures.get('agendaList')?.attendeeLines).toHaveLength(ROWS);
  });

  describe('every arrangement renders the same items from the same data', () => {
    for (const format of HOME_FORMATS) {
      it(format, () => {
        expect(signatures.get(format)).toEqual(signatures.get('agendaList'));
      });
    }
  });

  describe('agendaList is the screen that ships', () => {
    it('renders the captured pre-format DOM element for element', () => {
      expect(scheduleBody(renderHome('agendaList'))).toBe(BASELINE);
    });

    it('is what <HomeShowcase> resolves with no theme and no override', () => {
      // `useFormat`'s last rung. Nothing is loaded in this environment, so the
      // screen must be the one that ships rather than a blank switch arm.
      expect(scheduleBody(render(<HomeShowcase classes={TEST_CLASSES} themeTabPreview />))).toBe(
        BASELINE,
      );
    });
  });
});
