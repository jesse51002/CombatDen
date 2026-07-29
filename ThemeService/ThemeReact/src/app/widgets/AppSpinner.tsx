// Ports ../../../../../CRM/lib/shared/widgets/app_spinner.dart and its
// `part` file sweep_painter.dart.
//
// "Sweep": a faint hairline ring with a single sapphire → accent-dark arc that
// orbits it, lengthening as it accelerates and shrinking as it eases. The
// trailing edge fades to nothing (a comet), the leading edge deepens. Honours
// reduced motion by rendering the static resting arc (`_staticPhase = 0.5`) and
// running no animation.
//
// TWO DEVIATIONS, both because a browser has no `CustomPainter`:
//
//  1. THE MOTION IS SAMPLED, NOT SOLVED. `_SweepPainter` evaluates
//     `easeInOutCubic` per frame for the head (over t∈[0,.75]) and the tail
//     (over t∈[.25,1]), with `sweepFrac = max(.06, head - tail)` and a start
//     angle of `(t + tail)` turns. Those exact curves are sampled at t = 0,
//     .25, .5, .75, 1 and written as keyframes (see ./AppSpinner.module.css),
//     with the browser interpolating between them. Same period (1400ms), same
//     minimum nub (.06 of a turn), same two-turns-per-cycle orbit.
//     `pathLength={1}` is what lets the dash values be those raw fractions.
//
//  2. THE ALONG-ARC GRADIENT IS LINEAR, NOT SWEEP. SVG has no conic/sweep
//     gradient for a stroke. A linear gradient in the ARC'S OWN rotating frame
//     carries the same three stops (transparent → arc → deeper head) across the
//     arc's dominant quadrant, which reads as the same comet.

import { useId } from 'react';

import { ADM } from '../tokens/adminTokens';

import styles from './AppSpinner.module.css';
import { cx } from './cx';

export interface AppSpinnerProps {
  /** Outer diameter. Defaults to `iconSizeLarge` (24), as in Dart. */
  size?: number;
  /** Stroke width of the arc + track. Defaults to ~1/9 of the diameter. */
  strokeWidth?: number;
  /**
   * Recolours the ring for a sapphire fill (the primary button's loading
   * state). Dart gets this from `AppPrimaryButton` passing `valueColor`
   * to a `CircularProgressIndicator` instead of using this widget at all.
   */
  onAccent?: boolean;
}

export function AppSpinner({ size = ADM.iconSizeLarge, strokeWidth, onAccent = false }: AppSpinnerProps) {
  const gradientId = useId();
  const stroke = strokeWidth ?? size / 9;
  const radius = (size - stroke) / 2;
  const center = size / 2;
  return (
    <svg
      className={cx(styles.spinner, onAccent && styles.onAccent)}
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      role="progressbar"
      aria-label="Loading"
    >
      <defs>
        <linearGradient id={gradientId} x1="1" y1="0.4" x2="0" y2="1">
          <stop offset="0" className={styles.stopTail} />
          <stop offset="0.4" className={styles.stopBody} />
          <stop offset="1" className={styles.stopHead} />
        </linearGradient>
      </defs>
      <circle
        className={styles.track}
        cx={center}
        cy={center}
        r={radius}
        fill="none"
        strokeWidth={stroke}
      />
      <circle
        className={styles.arc}
        cx={center}
        cy={center}
        r={radius}
        fill="none"
        stroke={`url(#${gradientId})`}
        strokeWidth={stroke}
        strokeLinecap="round"
        pathLength={1}
      />
    </svg>
  );
}
