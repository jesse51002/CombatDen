// Ports ../../../../../CRM/lib/showcase/booking_showcase.dart — a visual clone
// of the member app's CLASS-BOOKED CELEBRATION (`ClassBookedScreen`): a slow
// image scale-pop, the "Class Booked" caption sliding up under it, and the CTA
// fading in. It loops.
//
// THE ARITHMETIC, not the derived numbers (booking_showcase.dart:16-20):
//
//   imageScale    = 720ms                          the pop
//   bookedCascade = imageScale + reveal(260ms)     when the caption has landed
//   ctaFadeIn     = 220ms                          the CTA's own fade
//   loopHold      = 2200ms                         the finished frame's dwell
//   cycle         = bookedCascade + loopHold       one full loop
//
// The 260ms is `CelebrationTimings.revealMs` — the library's ported timing
// vocabulary, which is where the Dart const gets it from too, so the cascade is
// derived rather than restated.
//
// HOW IT ANIMATES. Dart drives three `AnimationController`s and two `Timer`s.
// Here the three entrances are CSS — a keyframe each, with `animation-delay`
// placing the beat — because they are one-shot property tweens that never need
// a per-frame value in JS. The only JS left is the loop: one interval bumping a
// counter that re-keys the body, which is exactly what `_cycle` does in Dart
// (`KeyedSubtree` there, `key` here) and what makes the CSS animations replay.
//
// Under `prefers-reduced-motion` the interval is never armed and the CSS
// animations are suppressed (../showcase/BookingShowcase.module.css), so the
// screen renders its finished state and stays there.

import { useEffect, useState } from 'react';
import {
  CelebrationTimings,
  EASE_OUT_QUART,
  SCALE_REVEAL_START_SCALE,
  ThemedImage,
  useThemeText,
} from 'theme-react';

import styles from './BookingShowcase.module.css';
import { showcaseAsset } from './showcaseAssets';
import { SLOT_CELEBRATION_IMAGE, SLOT_CLASS_BOOKED_HEADLINE } from './showcaseSlots';
import { showcaseStyle } from './showcaseTokens';
import { ShowcasePrimaryButton } from './support/ShowcasePrimaryButton';
import { ShowcaseScaffold } from './support/ShowcaseScaffold';
import { usePrefersReducedMotion } from './usePrefersReducedMotion';

/** `_kImageScaleDuration`. */
const IMAGE_SCALE_MS = 720;
/** `_kBookedCascadeDuration` — the pop plus one standard reveal. */
const BOOKED_CASCADE_MS = IMAGE_SCALE_MS + CelebrationTimings.revealMs;
/** `_kCtaFadeIn`. */
const CTA_FADE_IN_MS = 220;
/** `_kLoopHold` — how long the finished content sits before the loop restarts. */
const LOOP_HOLD_MS = 2200;
/** One full cycle: the cascade, then the hold. */
const CYCLE_MS = BOOKED_CASCADE_MS + LOOP_HOLD_MS;

/**
 * `_kCelebrationMaxHeight` — mirrors the member app's own cap so the showcase
 * keeps the real screen's proportions inside a tall phone frame.
 */
const CELEBRATION_MAX_HEIGHT = 420;

/**
 * The motion values the stylesheet reads. Derived from the constants above and
 * from the library's ported motion vocabulary, and written as CSS variables so
 * the `.module.css` restates no timing of its own. A module constant: none of
 * it depends on the theme or on a render.
 */
const MOTION_VARS = showcaseStyle({
  '--bk-image-scale-ms': `${String(IMAGE_SCALE_MS)}ms`,
  '--bk-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
  '--bk-reveal-delay-ms': `${String(IMAGE_SCALE_MS)}ms`,
  '--bk-reveal-offset': '12px',
  '--bk-cta-fade-ms': `${String(CTA_FADE_IN_MS)}ms`,
  '--bk-cta-delay-ms': `${String(BOOKED_CASCADE_MS)}ms`,
  '--bk-start-scale': String(SCALE_REVEAL_START_SCALE),
  '--bk-ease': EASE_OUT_QUART,
});

export interface BookingShowcaseProps {
  loop?: boolean;
  onCycleComplete?: (() => void) | undefined;
}

export function BookingShowcase({ loop = true, onCycleComplete }: BookingShowcaseProps) {
  const reduceMotion = usePrefersReducedMotion();
  // Re-keys the body so every CSS entrance replays — Dart's `_cycle`.
  const [cycle, setCycle] = useState(0);

  useEffect(() => {
    if (!loop || reduceMotion) return;
    const id = window.setInterval(() => {
      onCycleComplete?.();
      setCycle((current) => current + 1);
    }, CYCLE_MS);
    return () => {
      window.clearInterval(id);
    };
  }, [loop, reduceMotion, onCycleComplete]);

  return (
    <ShowcaseScaffold>
      <div key={cycle} className={styles.screen} style={MOTION_VARS}>
        <BookedContent />
        <div className={styles.ctaRow}>
          <ShowcasePrimaryButton text="Continue" fullWidth borderRadius="var(--sc-radius-big)" />
        </div>
      </div>
    </ShowcaseScaffold>
  );
}

/** `_BookedContent` — `Column(center, spacing: spacingBig)`. */
function BookedContent() {
  const headline = useThemeText(SLOT_CLASS_BOOKED_HEADLINE, 'Class Booked');
  return (
    <div className={styles.content}>
      {/*
        `ScaleReveal(duration: 720)` — ease-out-quart, opacity 0 -> 1 and scale
        `SCALE_REVEAL_START_SCALE` -> 1. The library exports both the curve and
        the start scale; the CSS module reads them as its keyframe values.
      */}
      <div
        className={styles.celebration}
        style={{ maxHeight: `${String(CELEBRATION_MAX_HEIGHT)}px` }}
      >
        <ThemedImage
          className={styles.celebrationImg}
          slot={SLOT_CELEBRATION_IMAGE}
          fallbackSrc={showcaseAsset('class_booked_celebration.png')}
          alt=""
        />
      </div>
      {/* `StaggeredReveal(delay: 720)` — fade + a 12px slide up, ease-out-quart. */}
      <p className={styles.headline}>{headline}</p>
    </div>
  );
}
