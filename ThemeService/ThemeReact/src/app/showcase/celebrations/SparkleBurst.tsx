// Ports ../../../../../../CRM/lib/showcase/celebrations/sparkle_burst.dart — a
// clone of MobileApp's `SparkleBurst`: a decorative one-shot sparkle scatter
// that animates in around a hero image, rewired to `--sc-*`.
//
// PURE CSS AFTER MOUNT. Dart drives one `AnimationController` and recomputes
// every particle's opacity and scale each frame, because a Flutter `Transform`
// has no declarative timeline. Here each particle's slice of the window is a
// fixed `animation-delay` + `animation-duration` (see ./sparkleGeometry.ts), so
// twelve CSS animations replace the controller entirely — the component itself
// never re-renders and never touches a ref.
//
// The star is a `clip-path` over a `--sc-primary` box, not an SVG: see
// ./sparkleGeometry.ts for why, and for the point list it is derived from.
//
// LOOPING is the CALLER's job, exactly as in Dart — the hero screen re-keys the
// burst each cycle and the CSS animations replay from the top.

import { EASE_OUT_QUART } from 'theme-react';

import { cx } from '../cx';
import { showcaseStyle } from '../showcaseTokens';

import styles from './SparkleBurst.module.css';
import {
  SPARKLE_FADE_MS,
  SPARKLE_SCATTER,
  SPARKLE_START_SCALE,
  SPARKLE_STAR_CLIP_PATH,
  sparkleDelayMs,
} from './sparkleGeometry';

/** The motion the stylesheet reads. Theme-independent, so a module constant. */
const BURST_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--sp-star': SPARKLE_STAR_CLIP_PATH,
  '--sp-fade-ms': `${String(SPARKLE_FADE_MS)}ms`,
  '--sp-start-scale': String(SPARKLE_START_SCALE),
  '--sp-ease': EASE_OUT_QUART,
});

export interface SparkleBurstProps {
  /**
   * `SparkleBurst.size` — the edge of the square the scatter centres in.
   *
   * OMIT IT to let the caller's own class size the box, which is how every
   * current call site uses it: Dart wraps the burst in `Positioned.fill`, and a
   * filled box takes the STACK's size regardless of the `size` argument. An
   * inline width beside a `position: absolute; inset: 0` would fight it and
   * move the centre.
   */
  size?: number | undefined;
  /** `SparkleBurst.delay` — pushes every particle's start back by this much. */
  delayMs?: number | undefined;
  className?: string | undefined;
}

export function SparkleBurst({ size, delayMs = 0, className }: SparkleBurstProps) {
  const count = SPARKLE_SCATTER.length;
  return (
    <div
      className={cx(styles.burst, className)}
      style={showcaseStyle(
        BURST_VARS,
        size === undefined ? undefined : { width: `${String(size)}px`, height: `${String(size)}px` },
      )}
      aria-hidden="true"
    >
      {SPARKLE_SCATTER.map((particle, index) => (
        <span
          // The scatter is a fixed const list, so the slot index IS the
          // particle's identity — two entries may share every field.
          key={index}
          className={styles.particle}
          style={showcaseStyle({
            '--sp-size': `${String(particle.size)}px`,
            '--sp-dx': `${String(particle.dx)}px`,
            '--sp-dy': `${String(particle.dy)}px`,
            '--sp-opacity': String(particle.opacity),
            '--sp-delay-ms': `${String(delayMs + sparkleDelayMs(index, count))}ms`,
          })}
        />
      ))}
    </div>
  );
}
