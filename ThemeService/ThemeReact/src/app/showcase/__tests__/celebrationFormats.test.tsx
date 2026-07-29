// The functional-equivalence gate for `celebration_format`, porting
// ../../../../../../MobileApp/test/celebration_invariants_test.dart.
//
// An arrangement may change ARRANGEMENT ONLY. This asserts it mechanically, per
// card: every value of the vocabulary is rendered and the STAGE'S SUBTREE — the
// card's whole body, which is the only slot a preview card ships — is diffed
// against the one `centerHero` renders. An arrangement that wrapped the body,
// dropped a sparkle, or reached inside a card for something to promote fails
// here rather than in review. That is what makes "no feature added, none
// removed" verifiable instead of argued.
//
// WHY THE DIFF IS AN EXACT SUBTREE AND NOT A MULTISET OF PARTS. The Dart
// original counts `find.byType(CelebrationClose)` and friends because its
// layouts arrange FOUR slots. These cards ship exactly one — their body — so the
// equivalent, and strictly stronger, statement is that the body comes out
// byte-identical. Anything weaker would pass a frame that quietly re-parented
// half of it.
//
// FOUR CARDS, TWO VIEWS EACH. `MobileApp` has five `PostClassScaffold`
// consumers; the Flutter preview this island ports never carried a rank
// celebration, so there are four here. Each is a two-view screen (an intro that
// hands over to a settled statement), and BOTH views are put through all five
// values — an arrangement that only breaks once the count-up has landed is
// exactly the kind a screenshot of a looping animation cannot catch. The settled
// view is reached through `prefers-reduced-motion`, which is also how this file
// proves the frame did not cost the cards that behaviour.
//
// A STATIC RENDER, DELIBERATELY. `renderToStaticMarkup` runs no effects, so the
// three rAF drivers never write a frame-dependent `transform` into the tree and
// the diff is a statement about STRUCTURE rather than about when a timer
// happened to fire. The one thing a static render cannot prove — that the real
// client path mounts — is the last block below, which mounts all twenty states.
//
// The stylesheet is read off disk for the same reason ./showcaseTokens.test.ts
// does it: a `.css` import is an empty module under vitest, so an assertion
// against one would pass vacuously (../../../CLAUDE.md).

import { readFileSync } from 'node:fs';
import { cwd } from 'node:process';

import type { ReactElement } from 'react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';

import {
  CELEBRATION_LOWER_ZONE,
  CELEBRATION_SCRIM_HEIGHT,
} from '../celebrations/CelebrationFrame';
import frameStyles from '../celebrations/CelebrationFrame.module.css';
import type { CelebrationFormat } from '../formats';
import { CELEBRATION_FORMATS, FORMAT_SLOTS, setFormatOverride } from '../formats';
import { PointsShowcase } from '../PointsShowcase';
import pointsStyles from '../PointsShowcase.module.css';
import { RewardsCardShowcase } from '../RewardsCardShowcase';
import rewardsStyles from '../RewardsCardShowcase.module.css';
import { SC } from '../showcaseTokens';
import { StatsShowcase } from '../StatsShowcase';
import statsStyles from '../StatsShowcase.module.css';
import { WinsShowcase } from '../WinsShowcase';
import winsStyles from '../WinsShowcase.module.css';

// React only suppresses its "not configured to support act(...)" warning when
// the flag is set; vitest sets no such default.
(globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

// ---------------------------------------------------------------------------
// The harness
// ---------------------------------------------------------------------------

/** Which of a card's two views is on screen. */
type View = 'intro' | 'settled';

/**
 * jsdom implements no `matchMedia`, and every celebration screen reads it
 * (../usePrefersReducedMotion.ts) to decide whether to run its intro at all.
 * Flipping this is therefore how the settled view is reached without a clock.
 */
let reducedMotion = false;

beforeAll(() => {
  Object.defineProperty(window, 'matchMedia', {
    configurable: true,
    writable: true,
    value: (query: string) => ({
      media: query,
      matches: reducedMotion,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    }),
  });
});

afterEach(() => {
  reducedMotion = false;
  // The override store is a module singleton; a pin left behind would leak into
  // whichever test happens to run next.
  setFormatOverride(FORMAT_SLOTS.celebration, null);
});

/**
 * One card, and what its two views ship as. `root` is the class the view's own
 * top element carries and `elements` is how many elements that view renders —
 * both recorded from the rendering that shipped before `celebration_format`
 * existed, which is what makes the `centerHero` block below a regression pin
 * rather than a restatement of the current code.
 */
interface CardSpec {
  readonly name: string;
  readonly build: () => ReactElement;
  readonly views: Readonly<Record<View, { readonly root: string; readonly elements: number }>>;
  /** The views whose body is a bare `SizedBox.expand` — see `bleed`. */
  readonly bleeds: readonly View[];
}

const CARDS: readonly CardSpec[] = [
  {
    name: 'wins',
    build: () => <WinsShowcase />,
    // The recap has no intro/settled split: it cascades in place and holds.
    views: {
      intro: { root: winsStyles.content ?? '', elements: 323 },
      settled: { root: winsStyles.content ?? '', elements: 323 },
    },
    bleeds: [],
  },
  {
    name: 'points',
    build: () => <PointsShowcase />,
    views: {
      intro: { root: pointsStyles.sphere ?? '', elements: 29 },
      settled: { root: pointsStyles.points ?? '', elements: 229 },
    },
    bleeds: [],
  },
  {
    name: 'rewards',
    build: () => <RewardsCardShowcase />,
    views: {
      intro: { root: rewardsStyles.stage ?? '', elements: 31 },
      settled: { root: rewardsStyles.carouselLayout ?? '', elements: 25 },
    },
    bleeds: [],
  },
  {
    name: 'streak',
    build: () => <StatsShowcase />,
    views: {
      intro: { root: statsStyles.orbit ?? '', elements: 19 },
      settled: { root: statsStyles.stats ?? '', elements: 61 },
    },
    // The orbit is the one view that ships without the vertical inset its
    // sibling has (`CRM/lib/showcase/stats_showcase.dart:95`).
    bleeds: ['intro'],
  },
];

const VIEWS: readonly View[] = ['intro', 'settled'];

function render(spec: CardSpec, format: CelebrationFormat, view: View): HTMLElement {
  setFormatOverride(FORMAT_SLOTS.celebration, format);
  reducedMotion = view === 'settled';
  const host = document.createElement('div');
  host.innerHTML = renderToStaticMarkup(spec.build());
  return host;
}

function frame(host: HTMLElement): HTMLElement {
  const element = host.querySelector<HTMLElement>('[data-celebration-format]');
  if (element === null) throw new Error('no celebration frame rendered');
  return element;
}

/** The box the body settles in — `CelebrationStage`. */
function stage(host: HTMLElement): HTMLElement {
  const element = host.querySelector<HTMLElement>(`.${frameStyles.stage ?? ''}`);
  if (element === null) throw new Error('no celebration stage rendered');
  return element;
}

it('the frame publishes the classes every assertion below selects on', () => {
  // A CSS-Module key that stopped existing would turn every `querySelector`
  // into `.undefined` and quietly pass nothing.
  for (const key of ['frame', 'surface', 'stage', 'bleed', 'scrim', 'centerHero']) {
    expect(frameStyles[key], key).toBeTruthy();
  }
  for (const spec of CARDS) {
    for (const view of VIEWS) expect(spec.views[view].root, `${spec.name}/${view}`).toBeTruthy();
  }
});

// ---------------------------------------------------------------------------
// One choice, every card
// ---------------------------------------------------------------------------

describe('one arrangement drives every celebration card', () => {
  for (const format of CELEBRATION_FORMATS) {
    it(format, () => {
      // The hook lives in the frame, not in the screens, so a single pin moves
      // all four at once — with no shared registration file involved.
      for (const spec of CARDS) {
        for (const view of VIEWS) {
          const resolved = frame(render(spec, format, view)).dataset.celebrationFormat;
          expect(resolved, `${spec.name}/${view}`).toBe(format);
        }
      }
    });
  }
});

// ---------------------------------------------------------------------------
// The invariant
// ---------------------------------------------------------------------------

describe('no arrangement adds or drops anything', () => {
  for (const spec of CARDS) {
    for (const view of VIEWS) {
      it(`${spec.name} / ${view} renders the same body in all five`, () => {
        const shipped = stage(render(spec, 'centerHero', view)).innerHTML;
        expect(shipped).not.toBe('');

        for (const format of CELEBRATION_FORMATS) {
          if (format === 'centerHero') continue;
          const variant = stage(render(spec, format, view)).innerHTML;
          expect(variant, `${spec.name}/${view}/${format}`).toBe(shipped);
        }
      });
    }
  }
});

// ---------------------------------------------------------------------------
// `centerHero` is what ships, and it did not move
// ---------------------------------------------------------------------------

describe('centerHero renders exactly what shipped before the arrangements existed', () => {
  for (const spec of CARDS) {
    for (const view of VIEWS) {
      it(`${spec.name} / ${view}`, () => {
        const host = render(spec, 'centerHero', view);
        const body = stage(host);

        // The stage hands the view's own root straight through — no wrapper was
        // inserted between the arrangement and the card.
        expect(body.children).toHaveLength(1);
        expect(body.children[0]?.className).toContain(spec.views[view].root);

        // And the view renders element for element what it shipped.
        expect(body.getElementsByTagName('*')).toHaveLength(spec.views[view].elements);

        // The shipped arrangement floats nothing over the card and paints no
        // surface behind it: it is the plain padded canvas it always was.
        expect(host.querySelector(`.${frameStyles.scrim ?? ''}`)).toBeNull();
        expect(frame(host).className).toContain(frameStyles.centerHero ?? '');
      });
    }
  }

  it('the streak orbit keeps the one inset asymmetry the preview ships', () => {
    // Only that view asks for `bleed`, and it must not spread to its siblings:
    // every other body ships inside the `Padding(vertical: spacingBig)`.
    for (const spec of CARDS) {
      for (const view of VIEWS) {
        const bleeding = stage(render(spec, 'centerHero', view)).className.includes(
          frameStyles.bleed ?? '',
        );
        expect(bleeding, `${spec.name}/${view}`).toBe(spec.bleeds.includes(view));
      }
    }
  });
});

// ---------------------------------------------------------------------------
// The stylesheet — where the geometry actually lives
// ---------------------------------------------------------------------------

const SHEET_PATH = `${cwd()}/src/app/showcase/celebrations/CelebrationFrame.module.css`;
const SHEET = readFileSync(SHEET_PATH, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

/** `selector -> its declarations`, in source order. */
const RULES = new Map<string, string[]>(
  [...SHEET.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((match) => [
    (match[1] ?? '').trim().replace(/\s+/g, ' '),
    (match[2] ?? '')
      .split(';')
      .map((declaration) => declaration.trim().replace(/\s+/g, ' '))
      .filter(Boolean),
  ]),
);

describe('the arrangements are three variables and, at most, one surface', () => {
  it('centerHero is the shipped geometry, value for value', () => {
    // `padStandard` + each card's own `Padding(vertical: spacingBig) > Center`,
    // and nothing else. This is the assertion a screenshot of a looping
    // animation cannot make.
    expect(RULES.get('.centerHero')).toEqual([
      '--cf-frame-inset-x: var(--sc-screen-padding-x)',
      '--cf-stage-inset-top: var(--sc-spacing-big)',
      '--cf-stage-inset-bottom: var(--sc-spacing-big)',
    ]);

    // And it is the only rule that mentions it — the shipped value gets no
    // surface, no scrim and no override of the shared boxes.
    const mentions = [...RULES.keys()].filter((selector) => selector.includes('centerHero'));
    expect(mentions).toEqual(['.centerHero']);
  });

  it('only cardReveal and splitBand paint a surface', () => {
    const painted = [...RULES.entries()]
      .filter(([, declarations]) =>
        declarations.some((declaration) => declaration.startsWith('background')),
      )
      .map(([selector]) => selector);
    // The scrim is a gradient over the canvas, not a surface under the body.
    expect(painted).toEqual(['.cardReveal .surface', '.splitBand .surface', '.scrim']);
  });

  it('only figureTop moves the anchor, and only the two seamed values reserve the lower zone', () => {
    const setters = (property: string): string[] =>
      [...RULES.entries()]
        .filter(([, declarations]) =>
          declarations.some((declaration) => declaration.startsWith(`${property}:`)),
        )
        .map(([selector]) => selector);

    expect(setters('--cf-stage-anchor')).toEqual(['.figureTop']);

    const reserves = [...RULES.entries()]
      .filter(([, declarations]) =>
        declarations.some((declaration) => declaration.includes('var(--cf-lower-zone)')),
      )
      .map(([selector]) => selector);
    expect(reserves).toEqual(['.splitBand', '.fullBleed']);
  });

  it('nothing in the frame ever scrolls', () => {
    // `overflow-y: auto` computes `overflow-x` to `auto`, which would crop the
    // sparkle burst and the cover flow — the whole reason these screens are the
    // ones that do not scroll (../../../CLAUDE.md, "Things that will bite").
    const overflows = [...RULES.values()]
      .flat()
      .filter((declaration) => declaration.startsWith('overflow'));
    expect(overflows).not.toHaveLength(0);
    for (const declaration of overflows) expect(declaration).toBe('overflow: visible');
  });
});

describe('the reserved lower zone is the member app’s own arithmetic', () => {
  it('kCelebrationCtaZone', () => {
    // 48 + spacingBig * 2 — the action's height, the gap above it, the inset
    // below it. Reserved by splitBand and fullBleed even though these preview
    // cards draw nothing in it, so the seam sits where the real screen puts it.
    expect(CELEBRATION_LOWER_ZONE).toBe(48 + SC.spacingBig * 2);
    expect(CELEBRATION_LOWER_ZONE).toBe(112);
  });

  it('CelebrationScrim._kHeight overlaps the stage by one spacingBig', () => {
    expect(CELEBRATION_SCRIM_HEIGHT).toBe(CELEBRATION_LOWER_ZONE + SC.spacingBig);
    expect(CELEBRATION_SCRIM_HEIGHT).toBe(144);
  });
});

// ---------------------------------------------------------------------------
// The differences the layouts DO promise
// ---------------------------------------------------------------------------

describe('fullBleed is the only value that floats a scrim', () => {
  for (const format of CELEBRATION_FORMATS) {
    it(format, () => {
      for (const spec of CARDS) {
        const host = render(spec, format, 'settled');
        const scrim = host.querySelectorAll(`.${frameStyles.scrim ?? ''}`);
        expect(scrim, `${spec.name}/${format}`).toHaveLength(format === 'fullBleed' ? 1 : 0);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// The client path
// ---------------------------------------------------------------------------

describe('every card mounts in every arrangement', () => {
  // Twenty states, on the real client renderer: the rAF drivers resolve their
  // refs, the loop timers arm, and the reduced-motion listener attaches. A
  // static render proves the tree; this proves it runs.
  for (const format of CELEBRATION_FORMATS) {
    for (const spec of CARDS) {
      it(`${format} / ${spec.name}`, () => {
        setFormatOverride(FORMAT_SLOTS.celebration, format);
        const host = document.createElement('div');
        document.body.appendChild(host);
        const root = createRoot(host);
        act(() => {
          root.render(spec.build());
        });

        expect(frame(host).dataset.celebrationFormat).toBe(format);
        expect(stage(host).children).toHaveLength(1);

        act(() => {
          root.unmount();
        });
        host.remove();
      });
    }
  }
});
