// Pins the two pure helpers behind the Store screen — the port of
// CRM/lib/showcase/rewards/{points_headline,reward_card,sparkle_hero}.dart.

import { describe, expect, it } from 'vitest';

import { CelebrationTimings } from 'theme-react';

import { formatThousands } from '../formatPoints';
import {
  HERO_SPARKLES,
  HERO_STAGGER_SPAN,
  heroSparkleDelayMs,
  orderByDistance,
} from '../rewards/sparkleHeroGeometry';

describe('formatThousands', () => {
  it('groups in threes with a comma', () => {
    expect(formatThousands(3400)).toBe('3,400');
    expect(formatThousands(1000)).toBe('1,000');
    expect(formatThousands(1234567)).toBe('1,234,567');
  });

  it('leaves anything under 1000 unchanged, including negatives', () => {
    // The Dart's guard is `n < 1000`, so negatives fall through it too.
    expect(formatThousands(999)).toBe('999');
    expect(formatThousands(0)).toBe('0');
    expect(formatThousands(-4200)).toBe('-4200');
  });

  it('is NOT locale-aware', () => {
    // Intl.NumberFormat would print 3.400 under a German locale and silently
    // diverge from the phone this mirrors. The Dart walks digits itself.
    expect(formatThousands(3400)).not.toContain('.');
    expect(formatThousands(3400)).toBe('3,400');
  });
});

describe('orderByDistance', () => {
  it('ranks every sparkle exactly once', () => {
    const order = orderByDistance(HERO_SPARKLES);
    expect(order).toHaveLength(HERO_SPARKLES.length);
    expect([...order].sort((a, b) => a - b)).toEqual([...HERO_SPARKLES.keys()]);
  });

  it('sorts nearest-to-centre first, so the scatter lights up outward', () => {
    const order = orderByDistance(HERO_SPARKLES);
    const d2 = (i: number) => {
      const s = HERO_SPARKLES[i]!;
      return s.dx * s.dx + s.dy * s.dy;
    };
    for (let i = 1; i < order.length; i++) {
      expect(d2(order[i]!)).toBeGreaterThanOrEqual(d2(order[i - 1]!));
    }
  });

  it('is stable, matching Dart at this list size', () => {
    // Two sparkles equidistant from the centre must keep their list order.
    const tied = [
      { size: 4, dx: 10, dy: 0, opacity: 1 },
      { size: 4, dx: -10, dy: 0, opacity: 1 },
      { size: 4, dx: 0, dy: 5, opacity: 1 },
    ] as const;
    expect(orderByDistance(tied)).toEqual([2, 0, 1]);
  });
});

describe('heroSparkleDelayMs', () => {
  it('starts the nearest sparkle immediately', () => {
    expect(heroSparkleDelayMs(0, HERO_SPARKLES.length)).toBe(0);
  });

  it('spans HERO_STAGGER_SPAN of the sparkle window, never the whole of it', () => {
    const n = HERO_SPARKLES.length;
    const last = heroSparkleDelayMs(n - 1, n);
    const window = CelebrationTimings.sparkleWindowMs;
    expect(last).toBeLessThan(window * HERO_STAGGER_SPAN);
    // The last sparkle must still leave room for its own fade inside the
    // window — that is the point of staggering over 0.7 rather than 1.0.
    expect(last).toBeLessThan(window);
  });

  it('increases monotonically with rank', () => {
    const n = HERO_SPARKLES.length;
    for (let r = 1; r < n; r++) {
      expect(heroSparkleDelayMs(r, n)).toBeGreaterThan(heroSparkleDelayMs(r - 1, n));
    }
  });

  it('degrades to 0 on an empty set rather than dividing by zero', () => {
    expect(heroSparkleDelayMs(0, 0)).toBe(0);
    expect(Number.isNaN(heroSparkleDelayMs(3, 0))).toBe(false);
  });
});
