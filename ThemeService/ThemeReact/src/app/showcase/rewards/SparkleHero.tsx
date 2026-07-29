// Ports ../../../../../../CRM/lib/showcase/rewards/sparkle_hero.dart — a clone
// of MobileApp's `SparkleHero`: twenty-two sparkles scattered around a hero
// accent block (the "YOU EARNED / 3,400 / POINTS" statement), all of it lighting
// up outward from the number.
//
// PURE CSS AFTER MOUNT. Dart drives one `AnimationController` and recomputes
// every sparkle's opacity and scale each frame, because a Flutter `Transform`
// has no declarative timeline. Here each sparkle's slice of the window is a
// fixed `animation-delay` + `animation-duration` (see ./sparkleHeroGeometry.ts),
// so twenty-three CSS animations replace the controller entirely — the
// component never re-renders and never touches a ref. The accent block is the
// twenty-third: its opacity and scale are both linear in the SAME eased value,
// so one keyframe between two endpoints reproduces it exactly.
//
// The star shape comes from ../celebrations/sparkleGeometry.ts, whose
// `clip-path` is derived from the identical eight-point painter path this Dart
// file also carries. One polygon, two call sites.
//
// LOOPING is not this widget's business, in either language: the Points Store
// is a static surface and the hero animates once on mount.

import { CelebrationTimings, EASE_OUT_QUART } from 'theme-react';

import { SPARKLE_STAR_CLIP_PATH } from '../celebrations/sparkleGeometry';
import { showcaseStyle } from '../showcaseTokens';

import styles from './SparkleHero.module.css';
import {
  ACCENT_START_SCALE,
  HERO_FADE_MS,
  HERO_SPARKLES,
  HERO_START_SCALE,
  heroSparkleDelayMs,
  orderByDistance,
} from './sparkleHeroGeometry';

/** The motion the stylesheet reads. Theme-independent, so a module constant. */
const HERO_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--sh-star': SPARKLE_STAR_CLIP_PATH,
  '--sh-fade-ms': `${String(HERO_FADE_MS)}ms`,
  '--sh-window-ms': `${String(CelebrationTimings.sparkleWindowMs)}ms`,
  '--sh-start-scale': String(HERO_START_SCALE),
  '--sh-accent-start-scale': String(ACCENT_START_SCALE),
  '--sh-ease': EASE_OUT_QUART,
});

/** `_orderByDistance()` — a `late final` in Dart, a module constant here. */
const SPARKLE_ORDER = orderByDistance(HERO_SPARKLES);

export interface SparkleHeroProps {
  /** `SparkleHero.top` — the eyebrow above the number. */
  top: string;
  /** `SparkleHero.accent` — the number itself, already formatted. */
  accent: string;
  /** `SparkleHero.bottom` — the eyebrow below it. */
  bottom: string;
}

export function SparkleHero({ top, accent, bottom }: SparkleHeroProps) {
  return (
    // `Padding(horizontal: screenHorizontalPadding, vertical: paddingBig) >
    // Stack(alignment: center, clipBehavior: Clip.none)`.
    <div className={styles.hero} style={showcaseStyle(HERO_VARS)}>
      {SPARKLE_ORDER.map((sparkleIndex, rank) => {
        const sparkle = HERO_SPARKLES[sparkleIndex];
        if (sparkle === undefined) return null;
        return (
          <span
            key={sparkleIndex}
            className={styles.sparkle}
            aria-hidden="true"
            style={showcaseStyle({
              '--sh-size': `${String(sparkle.size)}px`,
              '--sh-dx': `${String(sparkle.dx)}px`,
              '--sh-dy': `${String(sparkle.dy)}px`,
              '--sh-opacity': String(sparkle.opacity),
              '--sh-delay-ms': `${String(heroSparkleDelayMs(rank, SPARKLE_ORDER.length))}ms`,
            })}
          />
        );
      })}

      {/* `_accentBlock` — `Column(min, spacing: spacingSmall)`. */}
      <div className={styles.accent}>
        <span className={styles.eyebrow}>{top}</span>
        <span className={styles.value}>{accent}</span>
        <span className={styles.eyebrow}>{bottom}</span>
      </div>
    </div>
  );
}
