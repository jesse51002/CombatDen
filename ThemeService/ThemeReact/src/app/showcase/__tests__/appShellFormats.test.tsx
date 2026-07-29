// The functional-equivalence gate for `app_shell_format`, porting
// ../../../../../../MobileApp/test/shell_invariants_test.dart.
//
// An arrangement may change ARRANGEMENT ONLY. This asserts it mechanically:
// every value of the vocabulary is rendered and its ELEMENT MULTISET is diffed
// against the one that ships. An arrangement that drops the QR action, loses a
// nav destination, or quietly adds a second mark fails here rather than in
// review. That is what makes the "no feature added, none removed" claim
// verifiable instead of argued.
//
// The Dart original diffs `find.byType(GymMark)` / `find.byType(InfoBar)`. The
// web has no widget types, so the multiset is keyed on the CSS-Module class
// each part carries — `.logo` IS the mark, `.rankBelt` IS the rank item. The
// class names are read from the same module the components import, so renaming
// a part in the component makes it count ZERO here, which the counts below
// report as a missing element rather than passing vacuously.
//
// Two things beyond the Dart test, both because the web can drop an element in
// ways Flutter cannot:
//
//   * `stacked` is pinned to the exact tree it shipped before the arrangements
//     existed, because six other screens render this chrome and a regression
//     there is invisible from any one of them.
//   * `markOnly`'s hidden gym name is checked in the DOM *and* in the
//     stylesheet, since "visually hidden" and "gone" differ only by which CSS
//     property does the hiding.

import { readFileSync } from 'node:fs';
import { cwd } from 'node:process';

import type { ReactElement } from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';

import type { AppShellFormat } from '../formats';
import { APP_SHELL_FORMATS, FORMAT_SLOTS, setFormatOverride } from '../formats';
import type { ShowcaseNavTab } from '../support/ShowcaseBottomNav';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import navStyles from '../support/ShowcaseBottomNav.module.css';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';
import topbarStyles from '../support/ShowcaseTopbar.module.css';

// React only suppresses its "not configured to support act(...)" warning when
// the flag is set; vitest sets no such default.
(globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

/**
 * A CSS-Module class, narrowed to a string. The generated typings widen every
 * class to optional, so reading one unchecked would hand `undefined` to a
 * `getElementsByClassName` that expects a string.
 */
function cls(name: string | undefined, id: string): string {
  if (name === undefined) throw new Error(`CSS Module class not found: ${id}`);
  return name;
}

/** The topbar parts this file identifies elements by. */
const TB = Object.freeze({
  logo: cls(topbarStyles.logo, 'logo'),
  gymName: cls(topbarStyles.gymName, 'gymName'),
  gymNameBig: cls(topbarStyles.gymNameBig, 'gymNameBig'),
  gymNameSmall: cls(topbarStyles.gymNameSmall, 'gymNameSmall'),
  chevron: cls(topbarStyles.chevron, 'chevron'),
  rankBelt: cls(topbarStyles.rankBelt, 'rankBelt'),
  iconValue: cls(topbarStyles.iconValue, 'iconValue'),
  iconValueImage: cls(topbarStyles.iconValueImage, 'iconValueImage'),
  qrCode: cls(topbarStyles.qrCode, 'qrCode'),
  visuallyHidden: cls(topbarStyles.visuallyHidden, 'visuallyHidden'),
});

/** The bottom-nav parts. */
const NV = Object.freeze({
  nav: cls(navStyles.nav, 'nav'),
  pill: cls(navStyles.pill, 'pill'),
  item: cls(navStyles.item, 'item'),
  label: cls(navStyles.label, 'label'),
  visuallyHidden: cls(navStyles.visuallyHidden, 'visuallyHidden'),
});

type TopbarMode = 'bigLogo' | 'nameOnly';

const MODES: readonly TopbarMode[] = ['bigLogo', 'nameOnly'];
const GYM_NAME = 'Global MMA';
const STREAK_DAYS = 12;
const POINTS_LABEL = '2,480';

const mounted: { root: ReturnType<typeof createRoot>; host: HTMLElement }[] = [];

function render(element: ReactElement): HTMLElement {
  const host = document.createElement('div');
  document.body.appendChild(host);
  const root = createRoot(host);
  act(() => {
    root.render(element);
  });
  mounted.push({ root, host });
  return host;
}

afterEach(() => {
  for (const { root, host } of mounted.splice(0)) {
    act(() => {
      root.unmount();
    });
    host.remove();
  }
  // The override store is a module singleton; a pin left behind would leak into
  // whichever test happens to run next.
  setFormatOverride(FORMAT_SLOTS.appShell, null);
});

function topbar(format: AppShellFormat, mode: TopbarMode): HTMLElement {
  return render(
    <ShowcaseTopbar
      formatOverride={format}
      mode={mode}
      gymName={GYM_NAME}
      streakDays={STREAK_DAYS}
      pointsLabel={POINTS_LABEL}
      rankBadgeAsset="icon_rank_belt.png"
    />,
  );
}

function nav(format: AppShellFormat, selected: ShowcaseNavTab = 'home'): HTMLElement {
  return render(<ShowcaseBottomNav formatOverride={format} selected={selected} />);
}

// ---------------------------------------------------------------------------
// The element multiset
// ---------------------------------------------------------------------------

/**
 * The parts a topbar is made of, keyed by the class each one carries. The three
 * name rungs collapse to one entry on purpose: an arrangement is allowed to
 * change how prominent the gym name is, and forbidden to remove it.
 */
const TOPBAR_PARTS: readonly (readonly [string, readonly string[]])[] = [
  ['mark', [TB.logo]],
  ['name', [TB.gymName, TB.gymNameBig, TB.gymNameSmall]],
  ['switchChevron', [TB.chevron]],
  ['stat:rank', [TB.rankBelt]],
  ['stat:iconValue', [TB.iconValue]],
  ['stat:qr', [TB.qrCode]],
];

/** `part -> how many of it the arrangement rendered`. */
function partCounts(host: HTMLElement): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const [part, classes] of TOPBAR_PARTS) {
    counts[part] = classes.reduce(
      (total, className) => total + host.getElementsByClassName(className).length,
      0,
    );
  }
  return counts;
}

describe('every shell arrangement carries every topbar element', () => {
  for (const format of APP_SHELL_FORMATS) {
    for (const mode of MODES) {
      it(`${format} / ${mode}`, () => {
        const counts = partCounts(topbar(format, mode));

        // The switch-gym affordance is always present, even where the layout
        // does not lay the name out (markOnly).
        expect(counts.name).toBe(1);
        expect(counts.switchChevron).toBe(1);

        // The stat bar always carries its four items: rank, streak, points, QR.
        expect(counts['stat:rank']).toBe(1);
        expect(counts['stat:iconValue']).toBe(2);
        expect(counts['stat:qr']).toBe(1);
      });
    }
  }
});

describe('no arrangement adds or drops a part relative to the shipped one', () => {
  for (const format of APP_SHELL_FORMATS) {
    for (const mode of MODES) {
      // `markOnly` + `nameOnly` is the ONE documented variance, asserted
      // explicitly below rather than skipped.
      const documentedVariance = format === 'markOnly' && mode === 'nameOnly';
      if (documentedVariance) continue;

      it(`${format} / ${mode} matches stacked`, () => {
        const shipped = partCounts(topbar('stacked', mode));
        const variant = partCounts(topbar(format, mode));
        expect(variant).toEqual(shipped);
      });
    }
  }

  it('markOnly is the one arrangement that shows the mark on every screen', () => {
    // The mark IS that layout, so it ignores the screen-level `nameOnly` hint —
    // and the name, not the mark, is what gets hidden instead. Every OTHER part
    // still matches the shipped arrangement element for element.
    const shipped = partCounts(topbar('stacked', 'nameOnly'));
    const variant = partCounts(topbar('markOnly', 'nameOnly'));

    expect(shipped.mark).toBe(0);
    expect(variant.mark).toBe(1);
    expect({ ...variant, mark: 0 }).toEqual(shipped);
  });

  it('the mark otherwise follows the screen-level prominence hint', () => {
    for (const format of APP_SHELL_FORMATS) {
      expect(partCounts(topbar(format, 'bigLogo')).mark).toBe(1);
      if (format === 'markOnly') continue;
      expect(partCounts(topbar(format, 'nameOnly')).mark).toBe(0);
    }
  });
});

// ---------------------------------------------------------------------------
// `stacked` is what ships, and it did not move
// ---------------------------------------------------------------------------

/**
 * The rendered tree as `tag.class.class`, one indented line per element, with
 * the CSS-Module hash suffix stripped so the expectation is readable.
 */
function outline(node: Element, depth = 0): string[] {
  const raw = node.getAttribute('class');
  const classes =
    raw === null
      ? ''
      : raw
          .split(/\s+/)
          .filter(Boolean)
          .map((name) => `.${name.replace(/^_(.+)_[0-9a-f]+$/, '$1')}`)
          .join('');
  const lines = [`${'  '.repeat(depth)}${node.tagName.toLowerCase()}${classes}`];
  for (const child of Array.from(node.children)) lines.push(...outline(child, depth + 1));
  return lines;
}

function tree(host: HTMLElement): string {
  return Array.from(host.children).flatMap((child) => outline(child)).join('\n');
}

describe('stacked renders exactly what shipped before the arrangements existed', () => {
  // Captured from the working tree BEFORE `app_shell_format` was wired in, so
  // this is a genuine before/after pin rather than a snapshot of the new code.
  // Six other screens render this chrome; if one of them changes appearance,
  // this is the test that says so.
  it('bigLogo', () => {
    expect(tree(topbar('stacked', 'bigLogo'))).toBe(
      [
        'div.topbar',
        '  div.gymHeader',
        '    img.logo',
        '    div.gymNameRow',
        '      span.gymNameBig',
        '      svg.chevron',
        '        path',
        '  div.infoBar',
        '    div.cell',
        '      img.rankBelt',
        '    div.cell',
        '      div.iconValue',
        '        span.iconValueText',
        '        img.iconValueImage',
        '    div.cell',
        '      div.iconValue',
        '        span.iconValueText',
        '        img.iconValueImage',
        '    div.cell',
        '      img.qrCode',
      ].join('\n'),
    );
  });

  it('nameOnly', () => {
    expect(tree(topbar('stacked', 'nameOnly'))).toBe(
      [
        'div.topbar',
        '  div.gymNameRow',
        '    span.gymName',
        '    svg.chevron',
        '      path',
        '  div.infoBar',
        '    div.cell',
        '      img.rankBelt',
        '    div.cell',
        '      div.iconValue',
        '        span.iconValueText',
        '        img.iconValueImage',
        '    div.cell',
        '      div.iconValue',
        '        span.iconValueText',
        '        img.iconValueImage',
        '    div.cell',
        '      img.qrCode',
      ].join('\n'),
    );
  });

  it('keeps the shipped stat extents, which are inline and therefore silent', () => {
    const host = topbar('stacked', 'bigLogo');
    const images = Array.from(
      host.getElementsByClassName(TB.iconValueImage),
    ) as HTMLElement[];
    expect(images.map((img) => [img.style.width, img.style.height])).toEqual([
      ['22px', '30px'],
      ['22px', '22px'],
    ]);
  });

  it('the four-up nav', () => {
    expect(tree(nav('stacked'))).toBe(
      [
        'nav.nav',
        '  div.item',
        '    svg',
        '      path',
        '      path',
        '    span.label',
        '  div.item',
        '    svg',
        '      circle',
        '      path',
        '    span.label',
        '  div.item',
        '    svg',
        '      rect',
        '      path',
        '      path',
        '    span.label',
        '  div.item',
        '    svg',
        '      rect',
        '      path',
        '    span.label',
      ].join('\n'),
    );
    const bar = nav('stacked').firstElementChild as HTMLElement;
    expect(bar.style.height).toBe('64px');
  });

  it('is what an unpinned theme resolves to, so the screens need pass nothing', () => {
    const pinned = tree(topbar('stacked', 'bigLogo'));
    const resolved = render(
      <ShowcaseTopbar
        mode="bigLogo"
        gymName={GYM_NAME}
        streakDays={STREAK_DAYS}
        pointsLabel={POINTS_LABEL}
        rankBadgeAsset="icon_rank_belt.png"
      />,
    );
    expect(tree(resolved)).toBe(pinned);
  });
});

// ---------------------------------------------------------------------------
// markOnly: the name leaves the screen, not the app
// ---------------------------------------------------------------------------

/** The element carrying the gym name, wherever an arrangement put it. */
function gymNameElement(host: HTMLElement): HTMLElement {
  const found = Array.from(host.querySelectorAll('span')).find(
    (span) => span.textContent === GYM_NAME,
  );
  expect(found).toBeDefined();
  return found as HTMLElement;
}

describe('markOnly keeps the gym name reachable', () => {
  it('the name is still in the document and still reads as the gym name', () => {
    const host = topbar('markOnly', 'bigLogo');
    expect(host.textContent).toContain(GYM_NAME);
    expect(gymNameElement(host).textContent).toBe(GYM_NAME);
  });

  it('nothing between the name and the root hides it from assistive tech', () => {
    const host = topbar('markOnly', 'nameOnly');
    for (
      let node: HTMLElement | null = gymNameElement(host);
      node !== null && node !== host;
      node = node.parentElement
    ) {
      expect(node.getAttribute('aria-hidden')).toBeNull();
      expect(node.hasAttribute('hidden')).toBe(false);
      expect(node.style.display).not.toBe('none');
      expect(node.style.visibility).not.toBe('hidden');
    }
  });

  it('the switch chevron travels with it, so the affordance is whole', () => {
    const host = topbar('markOnly', 'nameOnly');
    const row = gymNameElement(host).parentElement;
    expect(row).not.toBeNull();
    expect(row?.classList.contains(TB.visuallyHidden)).toBe(true);
    expect(row?.getElementsByClassName(TB.chevron)).toHaveLength(1);
  });

  it('hides by clipping, never by removal', () => {
    // The DOM assertions above cannot see the stylesheet, and `display: none`
    // is exactly the change that would pass them while emptying the
    // accessibility tree. vitest runs with `css: false` — a `.css` import hands
    // back an empty module, `?raw` included — so the sheet is read off disk,
    // the same way ../../__tests__/tokens.test.ts reads its own.
    for (const sheet of ['ShowcaseTopbar', 'ShowcaseBottomNav']) {
      const css = readFileSync(
        `${cwd()}/src/app/showcase/support/${sheet}.module.css`,
        'utf8',
      );
      const rule = /\.visuallyHidden\s*\{([^}]*)\}/.exec(css)?.[1];
      expect(rule, `${sheet}.module.css declares .visuallyHidden`).toBeDefined();
      expect(rule).toContain('clip-path');
      expect(rule).not.toContain('display: none');
      expect(rule).not.toContain('visibility: hidden');
    }
  });
});

// ---------------------------------------------------------------------------
// The bottom nav
// ---------------------------------------------------------------------------

const NAV_LABELS = ['Home', 'Rank', 'Reward', 'Videos'];

describe('every shell arrangement keeps all four nav destinations in order', () => {
  for (const format of APP_SHELL_FORMATS) {
    it(`${format}`, () => {
      const host = nav(format, 'rank');
      const items = Array.from(host.getElementsByClassName(NV.item)) as HTMLElement[];

      expect(items).toHaveLength(4);
      expect(
        Array.from(host.getElementsByClassName(NV.label)).map((el) => el.textContent),
      ).toEqual(NAV_LABELS);

      // Exactly one destination reads as active, and it is the selected one.
      const active = items.filter((item) => item.style.color === 'var(--sc-accent)');
      expect(active).toHaveLength(1);
      expect(active[0]?.textContent).toContain('Rank');

      // Every destination still resolves its `nav_*` icon slot: <ThemeIcon>
      // renders the bundled glyph until an override has probed, so one glyph
      // per item is what "the slot is still being asked for" looks like with no
      // theme loaded. Both layouts render the same <NavItem>, which is what
      // makes that true of the pill as well.
      expect(host.querySelectorAll('svg')).toHaveLength(4);
    });
  }

  it('the pill lays no label out but every destination keeps its name', () => {
    const host = nav('markOnly');
    const labels = Array.from(host.getElementsByClassName(NV.label));
    expect(labels.map((el) => el.textContent)).toEqual(NAV_LABELS);
    for (const label of labels) {
      expect(label.classList.contains(NV.visuallyHidden)).toBe(true);
      expect(label.getAttribute('aria-hidden')).toBeNull();
    }
  });

  it('only markOnly floats the nav; the rest keep the four-up bar', () => {
    for (const format of APP_SHELL_FORMATS) {
      const host = nav(format);
      const floats = host.getElementsByClassName(NV.pill).length === 1;
      expect(floats).toBe(format === 'markOnly');
      expect(host.getElementsByClassName(NV.nav)).toHaveLength(floats ? 0 : 1);
    }
  });
});

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

describe('the arrangement resolves from the slot, not from a screen', () => {
  it('an override pins both halves of the chrome at once', () => {
    setFormatOverride(FORMAT_SLOTS.appShell, 'markOnly');
    const bar = topbar('stacked', 'bigLogo');
    // An explicit `formatOverride` still wins — that is what the test harness
    // and a side-by-side preview rely on.
    expect(bar.getElementsByClassName(TB.visuallyHidden)).toHaveLength(0);

    const chrome = render(
      <>
        <ShowcaseTopbar
          mode="bigLogo"
          gymName={GYM_NAME}
          streakDays={STREAK_DAYS}
          pointsLabel={POINTS_LABEL}
          rankBadgeAsset="icon_rank_belt.png"
        />
        <ShowcaseBottomNav selected="home" />
      </>,
    );
    expect(chrome.getElementsByClassName(TB.visuallyHidden)).toHaveLength(1);
    expect(chrome.getElementsByClassName(NV.pill)).toHaveLength(1);
  });

  it('an unknown value degrades to the shipped arrangement', () => {
    setFormatOverride(FORMAT_SLOTS.appShell, 'someArrangementThisBuildPredates');
    expect(tree(render(<ShowcaseBottomNav selected="home" />))).toBe(tree(nav('stacked')));
  });
});
