// The functional-equivalence gate for `rewards_format`.
//
// Ports ../../../../../../MobileApp/test/rewards_invariants_test.dart, which
// pumps every value of the enum with the same fabricated store and diffs its
// component multiset against the contract. This does the same in the DOM: every
// arrangement is rendered with the SAME payload and its element census is
// compared, so an arrangement that loses a reward, drops a price tag, hands one
// card's redeem action to another, or duplicates a promoted reward fails here
// rather than in review.
//
// THE DOM HAS NO WIDGET TYPES, so the parts name themselves. Dart writes
// `find.byType(RewardPriceTag)`; here every part carries a `data-reward-part`
// and every card a `data-reward-card` (../rewardCardParts.tsx). The one
// exception is the redeem action, which needs no attribute — it is the card's
// only <button>, and "exactly one button per card" is precisely the Dart's own
// assertion.
//
// THE THIRD TEST IS THE ONE THAT MATTERS FOR `priceLadder`. Banding by cost
// invites a variant to print a NEW number — a gap, a percentage, a progress
// figure — which would break the invariant while still passing an element
// census. So the numeric literals rendered by each arrangement are collected
// per TEXT NODE (never across elements, so adjacency cannot merge two) and
// asserted identical across all five. The ladder may reorder and relabel; it
// may not put a digit on screen the shipped grid did not already have.

import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';

import { FORMAT_SLOTS, REWARDS_FORMATS, setFormatOverride } from '../../formats';
import { formatThousands } from '../../formatPoints';
import type { ShowcaseReward } from '../../showcaseContent';
import { RewardsShowcase } from '../../RewardsShowcase';
import { SHOWCASE_POINTS_STORE_DATA } from '../mockPointsStore';
import { BAND_ALMOST, BAND_READY, BAND_SAVING, rewardBands } from '../rewardBands';
import { StoreGrid } from '../StoreGrid';

// React 19 wants this flag before `act` will drive an update synchronously.
(globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const SAMPLE = SHOWCASE_POINTS_STORE_DATA;

afterEach(() => {
  setFormatOverride(FORMAT_SLOTS.rewards, null);
});

/** Renders the store under `format` and tears it down again. */
function withScreen(
  format: string,
  run: (host: HTMLElement) => void,
  rewards?: readonly ShowcaseReward[],
): void {
  setFormatOverride(FORMAT_SLOTS.rewards, format);
  const host = document.createElement('div');
  document.body.appendChild(host);
  const root = createRoot(host);
  try {
    act(() => {
      root.render(<RewardsShowcase rewards={rewards ?? null} />);
    });
    run(host);
  } finally {
    act(() => {
      root.unmount();
    });
    host.remove();
  }
}

function cards(host: HTMLElement): readonly HTMLElement[] {
  return Array.from(host.querySelectorAll<HTMLElement>('[data-reward-card]'));
}

function partsIn(card: HTMLElement, part: string): number {
  return card.querySelectorAll(`[data-reward-part="${part}"]`).length;
}

/**
 * Every numeric literal on screen, one text node at a time.
 *
 * Per NODE rather than over `textContent` on purpose: two inline elements can
 * sit flush against each other (the row layout puts the price tag hard beside
 * the cost), and a whole-subtree read would splice their digits into one token
 * in some arrangements and not others.
 */
function numbersOnScreen(host: HTMLElement): readonly string[] {
  const found: string[] = [];
  const walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT);
  let node = walker.nextNode();
  while (node !== null) {
    for (const match of (node.textContent ?? '').matchAll(/\d[\d,.]*/g)) found.push(match[0]);
    node = walker.nextNode();
  }
  return [...found].sort();
}

describe('every rewards format renders the whole store', () => {
  for (const format of REWARDS_FORMATS) {
    it(format, () => {
      withScreen(format, (host) => {
        // The chrome every arrangement carries.
        expect(host.textContent).toContain('Your Gym');
        expect(host.textContent).toContain('Points Store');
        expect(host.textContent).toContain('My Rewards');
        expect(host.textContent).toContain('YOU EARNED');
        expect(host.textContent).toContain(formatThousands(SAMPLE.totalPoints));
        expect(host.textContent).toContain('POINTS');
        expect(host.querySelectorAll('nav')).toHaveLength(1);

        // One card per reward — none dropped, none duplicated. `storefrontHero`
        // promotes the first reward OUT of the grid rather than copying it, and
        // this is where a copy would show up.
        expect(cards(host)).toHaveLength(SAMPLE.items.length);
        for (const item of SAMPLE.items) {
          const titles = Array.from(
            host.querySelectorAll('[data-reward-part="title"]'),
          ).filter((node) => node.textContent === item.title);
          expect(titles).toHaveLength(1);
        }
      });
    });
  }
});

describe('every card carries every element, in every format', () => {
  for (const format of REWARDS_FORMATS) {
    it(format, () => {
      withScreen(format, (host) => {
        for (const card of cards(host)) {
          expect(partsIn(card, 'image')).toBe(1);
          expect(partsIn(card, 'price-tag')).toBe(1);
          expect(partsIn(card, 'title')).toBe(1);
          expect(partsIn(card, 'cost')).toBe(1);

          // Exactly one redeem action, and it belongs to THIS card. An
          // arrangement that lifts the action out to one screen-level button
          // fails here, which is the intent.
          const actions = card.querySelectorAll('button');
          expect(actions).toHaveLength(1);
          expect(actions[0]?.textContent).toBe('Redeem');
        }
      });
    });
  }
});

describe('no format puts a number on screen that cardGrid does not', () => {
  let baseline: readonly string[] = [];
  beforeAll(() => {
    withScreen('cardGrid', (host) => {
      baseline = numbersOnScreen(host);
    });
  });

  it('the shipped grid prints the balance and every cost', () => {
    // Guards the guard: an empty or accidentally-truncated baseline would make
    // every comparison below pass vacuously.
    expect(baseline).toContain(formatThousands(SAMPLE.totalPoints));
    for (const item of SAMPLE.items) {
      expect(baseline).toContain(formatThousands(item.pointsCost));
    }
  });

  for (const format of REWARDS_FORMATS) {
    it(format, () => {
      withScreen(format, (host) => {
        expect(numbersOnScreen(host)).toEqual(baseline);
      });
    });
  }
});

describe('a one-reward store still shows that reward once', () => {
  const only: readonly ShowcaseReward[] = [
    {
      title: 'Free Week',
      imageUrl: 'https://example.test/free-week.png',
      priceLabel: 'Free',
      pointsCost: 800,
    },
  ];

  for (const format of REWARDS_FORMATS) {
    it(format, () => {
      withScreen(
        format,
        (host) => {
          expect(cards(host)).toHaveLength(1);
          expect(
            Array.from(host.querySelectorAll('[data-reward-part="title"]')).filter(
              (node) => node.textContent === 'Free Week',
            ),
          ).toHaveLength(1);
        },
        only,
      );
    });
  }
});

/**
 * `cardGrid` is the arrangement that SHIPS, so it is not enough for it to pass
 * the census — its markup must be the markup that was there before the format
 * seam existed. The string below was captured from the pre-seam build.
 *
 * Class attributes are stripped because CSS-module hashes move when a rule
 * moves file, and `data-*` because the census attributes above are new markup
 * for the gate rather than a change to the screen. What is left — tag
 * structure, image sources, and every word — is exactly what a tenant sees.
 */
const SHIPPED_STORE_GRID =
  '<div><div><div><div><img alt="Bring a friend" src="/src/app/showcase/assets/reward_bring_friend.png"><span>Free</span></div><div><div><span>Bring a friend</span></div><span>800 pts</span><button type="button"><span>Redeem</span></button></div></div><div><div><img alt="Private Training\n(15 min)" src="/src/app/showcase/assets/reward_private_training_short.png"><span>Free</span></div><div><div><span>Private Training\n(15 min)</span></div><span>1,800 pts</span><button type="button"><span>Redeem</span></button></div></div><div><div><img alt="Boxing gloves" src="/src/app/showcase/assets/reward_gloves.png"><span>10% off</span></div><div><div><span>Boxing gloves</span></div><span>2,500 pts</span><button type="button"><span>Redeem</span></button></div></div></div><div><div><div><img alt="Hand wraps" src="/src/app/showcase/assets/reward_hand_wraps.png"><span>30% off</span></div><div><div><span>Hand wraps</span></div><span>1,500 pts</span><button type="button"><span>Redeem</span></button></div></div><div><div><img alt="Gym t-shirt" src="/src/app/showcase/assets/reward_mma_tshirt.png"><span>Free</span></div><div><div><span>Gym t-shirt</span></div><span>2,200 pts</span><button type="button"><span>Redeem</span></button></div></div><div><div><img alt="Private Training" src="/src/app/showcase/assets/reward_private_training.png"><span>50% off</span></div><div><div><span>Private Training</span></div><span>3,500 pts</span><button type="button"><span>Redeem</span></button></div></div></div></div>';

/** Everything a tenant sees, with the styling hooks and test hooks removed. */
function structure(node: Element): string {
  const clone = node.cloneNode(true) as Element;
  for (const element of [clone, ...Array.from(clone.querySelectorAll('*'))]) {
    for (const name of element.getAttributeNames()) {
      if (name !== 'src' && name !== 'alt' && name !== 'type') element.removeAttribute(name);
    }
  }
  return clone.outerHTML;
}

describe('cardGrid is unchanged from what ships today', () => {
  it('renders the shipped two-column store, card for card', () => {
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);
    try {
      act(() => {
        root.render(<StoreGrid items={SAMPLE.items} />);
      });
      const grid = host.firstElementChild;
      expect(grid).not.toBeNull();
      expect(structure(grid as Element)).toBe(SHIPPED_STORE_GRID);
    } finally {
      act(() => {
        root.unmount();
      });
      host.remove();
    }
  });
});

describe('rewardBands', () => {
  const total = SAMPLE.totalPoints;

  it('bands by cost against the balance, cheapest first', () => {
    const bands = rewardBands(SAMPLE.items, total);
    expect(bands.map((band) => band.label)).toEqual([BAND_READY, BAND_ALMOST]);
    expect(bands[0]?.affordable).toBe(true);
    expect(bands[1]?.affordable).toBe(false);
    for (const band of bands) {
      const costs = band.items.map((item) => item.pointsCost);
      expect(costs).toEqual([...costs].sort((a, b) => a - b));
    }
  });

  it('puts every reward in exactly one band', () => {
    const bands = rewardBands(SAMPLE.items, total);
    const banded = bands.flatMap((band) => band.items.map((item) => item.title)).sort();
    expect(banded).toEqual(SAMPLE.items.map((item) => item.title).sort());
  });

  it('splits at the balance and at twice the balance', () => {
    const at = (cost: number) => ({ title: `#${String(cost)}`, priceLabel: 'Free', pointsCost: cost });
    const bands = rewardBands([at(100), at(101), at(200), at(201)], 100);
    expect(bands.map((band) => band.label)).toEqual([BAND_READY, BAND_ALMOST, BAND_SAVING]);
    expect(bands[0]?.items.map((item) => item.pointsCost)).toEqual([100]);
    expect(bands[1]?.items.map((item) => item.pointsCost)).toEqual([101, 200]);
    expect(bands[2]?.items.map((item) => item.pointsCost)).toEqual([201]);
  });

  it('drops an empty band rather than labelling nothing', () => {
    const bands = rewardBands([{ title: 'a', priceLabel: 'Free', pointsCost: 10 }], 100);
    expect(bands).toHaveLength(1);
    expect(bands[0]?.label).toBe(BAND_READY);
  });
});
