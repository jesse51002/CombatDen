// Ports ../../../../../../CRM/lib/showcase/support/streak_week_strip.dart — a
// clone of MobileApp's `StreakWeekStrip`: seven day badges, Sunday through
// Saturday, cascading in left-to-right from `baseDelayMs`.
//
// Two motions per badge, and Dart nests them: the outer `StaggeredReveal` fades
// and slides the badge in, and a completed day is additionally wrapped in
// `_PulseOnLand`, which scales 0.9 → 1 over `pulseDuration` on the SAME beat.
// They stay two elements here for the same reason they are two widgets there —
// one animates opacity and translate, the other scale, and a single element
// cannot run two `transform` animations at once.
//
// Both are CSS: each is a one-shot tween between fixed endpoints with a delay,
// which is the case keyframes exist for.

import { EASE_OUT_QUART, CelebrationTimings } from 'theme-react';

import { cx } from '../cx';
import { SC, showcaseStyle } from '../showcaseTokens';

import { CheckCircleIcon, CircleIcon } from './icons';
import styles from './StreakWeekStrip.module.css';

/** `StaggeredReveal.offset` — the slide the reveal travels, in px. */
const REVEAL_OFFSET_PX = 12;

/** `ShowcaseStreakDay` — one day in the strip. */
export interface ShowcaseStreakDay {
  readonly label: string;
  readonly completed: boolean;
}

/** `CelebrationTimings.badgeStagger * i`. */
export function streakBadgeDelayMs(baseDelayMs: number, index: number): number {
  return baseDelayMs + CelebrationTimings.badgeStaggerMs * index;
}

export interface StreakWeekStripProps {
  days: readonly ShowcaseStreakDay[];
  /** `StreakWeekStrip.baseDelay` — when the first badge's reveal starts. */
  baseDelayMs?: number | undefined;
}

export function StreakWeekStrip({ days, baseDelayMs = 0 }: StreakWeekStripProps) {
  return (
    <div className={styles.strip}>
      {days.map((day, index) => (
        // The week is a fixed seven-slot list, so the slot index IS the day's
        // identity — 'S' and 'T' each appear twice.
        <StreakDayBadge
          key={`${String(index)}-${day.label}`}
          day={day}
          delayMs={streakBadgeDelayMs(baseDelayMs, index)}
        />
      ))}
    </div>
  );
}

/**
 * `_StreakDayBadge`. A completed day takes the brand tint and the check; the
 * rest sit on the canvas at `text2nd`.
 */
function StreakDayBadge({ day, delayMs }: { day: ShowcaseStreakDay; delayMs: number }) {
  const Glyph = day.completed ? CheckCircleIcon : CircleIcon;
  return (
    <div
      className={styles.reveal}
      style={showcaseStyle({
        '--sw-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
        '--sw-pulse-ms': `${String(CelebrationTimings.pulseMs)}ms`,
        '--sw-delay-ms': `${String(delayMs)}ms`,
        '--sw-reveal-offset': `${String(REVEAL_OFFSET_PX)}px`,
        '--sw-ease': EASE_OUT_QUART,
      })}
    >
      <div className={cx(styles.badge, day.completed && styles.completed)}>
        <span className={styles.label}>{day.label}</span>
        <Glyph size={SC.iconSizeSm} className={styles.glyph} />
      </div>
    </div>
  );
}
