// Ports ../../../../../../CRM/lib/shared/widgets/animation/count_up_text.dart —
// a clone of MobileApp's `CountUpText`: an odometer that rolls 0 → `target` on
// a steep ease-out-expo curve, one vertical reel per digit position, each
// translated behind a one-digit window.
//
// WHY IT LIVES IN celebrations/ RATHER THAN A ONE-FILE animation/ FOLDER. The
// Dart keeps it in `lib/shared/widgets/animation/` because the kiosk's glance
// uses it too; this island has no kiosk, and the only readers are celebration
// surfaces — ./WinsTile.tsx today, the points recap next. It is the shared
// celebration primitive it looks like, so it sits with the others.
//
// WHY rAF AND NOT KEYFRAMES. Every other entrance in this island is a CSS
// animation, because it is one property tweened between two endpoints. This one
// is not: the reel offset is `min(eased * target / 10^p, maxIndex)` — a value
// DERIVED per frame from a single shared clock, and clamped, which no timing
// function expresses. So the driver is the sanctioned exception: one rAF loop
// writing `transform` straight to the strips, never through React state, so a
// 1400ms roll costs zero re-renders.
//
// THE STYLE IS INHERITED, not a prop. Dart takes a `TextStyle`; here the digits
// are real text inside the caller's own box, so `font`, `letter-spacing` and
// `color` cascade in from whatever `--sc-type-*` rung the caller set. That is
// also what makes the digit cell self-measuring — see the stylesheet.

import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';
import { CelebrationTimings } from 'theme-react';

import { cx } from '../cx';
import { usePrefersReducedMotion } from '../usePrefersReducedMotion';

import styles from './CountUpText.module.css';
import { Curves } from './curves';

/** Every digit, so the invisible sizer measures the widest — `_measureDigitCell`. */
const DIGITS: readonly number[] = Object.freeze([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

/** The attribute the driver finds its reels by. Set on each strip. */
const REEL_ATTR = 'data-reel-divisor';

export interface CountUpTextProps {
  target: number;
  /** `CountUpText.duration` — defaults to the celebration roll (1400ms). */
  durationMs?: number | undefined;
  /** `CountUpText.delay`. */
  delayMs?: number | undefined;
  /** `CountUpText.prefix` — e.g. the `+` of `"+160"`. */
  prefix?: string | undefined;
  /** `CountUpText.suffix`. */
  suffix?: string | undefined;
  className?: string | undefined;
}

/** `_digitCountFor` — how many reel positions `target` needs. */
export function digitCountFor(value: number): number {
  const abs = Math.abs(Math.trunc(value));
  return abs < 10 ? 1 : String(abs).length;
}

/**
 * `_DigitReelState`'s per-position constants: `_divisor` and `_maxIndex`. The
 * strip runs `0..maxIndex` and shows `i % 10`, so a position's last cell is
 * always the digit the roll must land on.
 */
export function reelSpec(target: number, position: number): { divisor: number; maxIndex: number } {
  const divisor = 10 ** position;
  return { divisor, maxIndex: Math.trunc(target / divisor) };
}

/**
 * `_DigitReel`'s per-frame offset: `(eased * target / divisor).clamp(0, maxIndex)`.
 * Returned in CELLS; the stylesheet turns it into a percentage of the strip.
 */
export function reelOffset(eased: number, target: number, divisor: number, maxIndex: number): number {
  const raw = (eased * target) / divisor;
  return raw < 0 ? 0 : raw > maxIndex ? maxIndex : raw;
}

export function CountUpText({
  target,
  durationMs = CelebrationTimings.countUpMs,
  delayMs = 0,
  prefix = '',
  suffix = '',
  className,
}: CountUpTextProps) {
  const reduceMotion = usePrefersReducedMotion();
  const rootRef = useRef<HTMLSpanElement | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (root === null) return;
    const strips = [...root.querySelectorAll<HTMLElement>(`[${REEL_ATTR}]`)];

    // `Transform.translate(0, -reelValue * digitHeight)`. Expressed as a
    // percentage of the STRIP so nothing has to be measured: the strip is
    // exactly `count` equal cells tall, so one cell is `100 / count` percent.
    const apply = (eased: number): void => {
      for (const strip of strips) {
        const divisor = Number(strip.dataset['reelDivisor']);
        const count = Number(strip.dataset['reelCount']);
        const offset = reelOffset(eased, target, divisor, count - 1);
        strip.style.transform = `translateY(${String((-offset / count) * 100)}%)`;
      }
    };

    // `MediaQuery.disableAnimationsOf` — land on the value and stay there.
    if (reduceMotion) {
      apply(1);
      return;
    }

    apply(0);
    let raf = 0;
    let startMs = 0;
    const frame = (now: number): void => {
      if (startMs === 0) startMs = now;
      const t = Math.min((now - startMs) / durationMs, 1);
      apply(Curves.easeOutExpo(t));
      if (t < 1) raf = requestAnimationFrame(frame);
    };
    // `Future.delayed(delay, () => _ctrl.forward())`.
    const timer = window.setTimeout(
      () => {
        raf = requestAnimationFrame(frame);
      },
      delayMs,
    );
    return () => {
      window.clearTimeout(timer);
      cancelAnimationFrame(raf);
    };
  }, [target, durationMs, delayMs, reduceMotion]);

  const positions = digitCountFor(target);
  const reels: ReactNode[] = [];
  for (let p = positions - 1; p >= 0; p--) {
    reels.push(<DigitReel key={`reel-${String(p)}`} target={target} position={p} />);
    // `if (p > 0 && p % 3 == 0) Text(',')` — the thousands separators.
    if (p > 0 && p % 3 === 0) {
      reels.push(
        <span key={`sep-${String(p)}`} className={styles.glyph}>
          ,
        </span>,
      );
    }
  }

  return (
    // Every cell of every strip is real text in the DOM, so a reader left to
    // itself would announce the whole reel ("0 1 2 … 160"). `role="img"` plus
    // the settled label makes the odometer one opaque value, which is what it
    // reads as on screen.
    <span
      ref={rootRef}
      className={cx(styles.root, className)}
      role="img"
      aria-label={`${prefix}${String(target)}${suffix}`}
    >
      {prefix !== '' && <span className={styles.glyph}>{prefix}</span>}
      {reels}
      {suffix !== '' && <span className={styles.glyph}>{suffix}</span>}
    </span>
  );
}

/** `_DigitReel` — one position's window and the strip that rolls behind it. */
function DigitReel({ target, position }: { target: number; position: number }) {
  const { divisor, maxIndex } = reelSpec(target, position);
  const count = maxIndex + 1;
  return (
    <span className={styles.reel}>
      {/*
        `_measureDigitCell`: Dart lays every digit out with a `TextPainter` and
        keeps the widest and tallest. The web's version is a one-cell grid with
        all ten digits stacked in it — the track sizes to the maximum, which is
        the same measurement, made by the layout engine in the real font.
      */}
      <span className={styles.sizer} aria-hidden="true">
        {DIGITS.map((digit) => (
          <span key={digit}>{digit}</span>
        ))}
      </span>
      <span
        className={styles.strip}
        data-reel-divisor={divisor}
        data-reel-count={count}
      >
        {Array.from({ length: count }, (_, i) => (
          <span key={i} className={styles.digit}>
            {i % 10}
          </span>
        ))}
      </span>
    </span>
  );
}
