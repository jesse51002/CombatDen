// Ports ../../../../../CRM/lib/showcase/stats_showcase.dart — an exact visual
// clone of the member app's post-class STREAK celebration (`StreakScreen` /
// `StreakBody`): a ring of small streak icons expands, spins and collapses back
// to the centre, the big streak icon pops up in its place and fades out, and
// then the week count, the caption and the week strip cascade in. It loops.
//
// TWO VIEWS, ONE SWITCH — the same shape as `_StatsShowcaseState`: the orbit
// runs for its own timeline, hands over to the stats statement, which holds for
// `_kStatsHold` before the whole thing restarts with a bumped `_cycle`. The
// cycle re-keys the orbit, which is what makes it replay; here it also re-keys
// the stats block so its CSS entrances replay with it.
//
// WHY THE ORBIT IS THE ONE rAF DRIVER IN THIS ISLAND. Every other entrance is
// one element tweening between fixed endpoints, which is a keyframe. The ring
// is not: eight icons share ONE clock and one radius that grows and then
// collapses, and their positions are `cos/sin(spin + i·2π/8) · radius` — a
// value that has to be recomputed per frame from that clock. So the driver
// writes `transform` straight to the elements' refs and never through React
// state: eight particles at 60fps must not cost eight re-renders. The maths
// itself is in ./streakOrbit.ts, where it can be asserted.
//
// The stats half needs none of that and gets none: the count-up drives itself
// (./celebrations/CountUpText.tsx), and the caption and week strip are CSS.

import { useEffect, useRef, useState } from 'react';
import { CelebrationTimings, EASE_OUT_QUART, ThemedImage } from 'theme-react';

import { CelebrationFrame } from './celebrations/CelebrationFrame';
import { CountUpText } from './celebrations/CountUpText';
import { showcaseAsset } from './showcaseAssets';
import { SLOT_STREAK_ICON } from './showcaseSlots';
import { showcaseStyle } from './showcaseTokens';
import type { ShowcaseStreakDay } from './support/StreakWeekStrip';
import { StreakWeekStrip } from './support/StreakWeekStrip';
import styles from './StatsShowcase.module.css';
import { ORBIT_COUNT, ORBIT_TOTAL_MS, STATS_HOLD_MS, orbitFrame, orbitLayout, orbitOffset } from './streakOrbit';
import { usePrefersReducedMotion } from './usePrefersReducedMotion';

// Dummy data — a clone of MobileApp's `mockStreakStats`. Not a customization
// slot, and not a member's real numbers.
/** `_kWeekCount`. */
const WEEK_COUNT = 3;
/** `_kSubtitle`. */
const SUBTITLE = 'Completed your 2nd class this week';
/** `_kWeekDays`. */
const WEEK_DAYS: readonly ShowcaseStreakDay[] = Object.freeze([
  Object.freeze({ label: 'S', completed: false }),
  Object.freeze({ label: 'M', completed: true }),
  Object.freeze({ label: 'T', completed: false }),
  Object.freeze({ label: 'W', completed: false }),
  Object.freeze({ label: 'T', completed: true }),
  Object.freeze({ label: 'F', completed: false }),
  Object.freeze({ label: 'S', completed: false }),
]);

/** `subtitleDelay` — the caption waits out the whole count-up roll. */
export const SUBTITLE_DELAY_MS = CelebrationTimings.countUpMs;
/** `stripDelay` — one standard stagger after that. */
export const STRIP_DELAY_MS = SUBTITLE_DELAY_MS + CelebrationTimings.revealStaggerMs;

/** `StaggeredReveal.offset` — the slide a reveal travels, in px. */
const REVEAL_OFFSET_PX = 12;

/** The motion values the stats stylesheet reads. Theme-independent. */
const STATS_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--st-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
  '--st-reveal-offset': `${String(REVEAL_OFFSET_PX)}px`,
  '--st-subtitle-delay-ms': `${String(SUBTITLE_DELAY_MS)}ms`,
  '--st-ease': EASE_OUT_QUART,
});

export interface StatsShowcaseProps {
  loop?: boolean;
  onCycleComplete?: (() => void) | undefined;
}

export function StatsShowcase({ loop = true, onCycleComplete }: StatsShowcaseProps) {
  const reduceMotion = usePrefersReducedMotion();
  const [cycle, setCycle] = useState(0);
  const [showStats, setShowStats] = useState(false);

  useEffect(() => {
    if (reduceMotion) return;
    // `_ctrl.forward().whenComplete(widget.onComplete)` → `_toStats`.
    const toStats = window.setTimeout(() => {
      setShowStats(true);
    }, ORBIT_TOTAL_MS);
    // `_hold = Timer(_kStatsHold, _restart)`, armed by `_toStats`. Collapsed
    // into one absolute deadline here so the pair re-arms as a unit each cycle.
    const restart = window.setTimeout(() => {
      onCycleComplete?.();
      if (!loop) return;
      setShowStats(false);
      setCycle((current) => current + 1);
    }, ORBIT_TOTAL_MS + STATS_HOLD_MS);
    return () => {
      window.clearTimeout(toStats);
      window.clearTimeout(restart);
    };
    // `cycle` is the dependency that re-arms the pair: `_restart` bumps it, the
    // effect tears down and re-runs, and the orbit below remounts on its key.
  }, [cycle, loop, reduceMotion, onCycleComplete]);

  // Reduced motion goes straight to the finished statement: the orbit is pure
  // motion, so there is no "end state" of it worth rendering.
  const settled = showStats || reduceMotion;

  return (
    // The celebration's arrangement — `PostClassScaffold`, resolved from the
    // tenant's `celebration_format` (./celebrations/CelebrationFrame.tsx).
    //
    // `bleed` is the one asymmetry this screen ships and it is carried through
    // rather than tidied away: the orbit is a bare `SizedBox.expand` while the
    // statement sits inside a `Padding(vertical: spacingBig)`
    // (stats_showcase.dart:95), so only the statement takes the arrangement's
    // vertical inset. `centerHero` has to render exactly what ships today.
    <CelebrationFrame bleed={!settled}>
      {settled ? <StatsContent key={cycle} /> : <StreakOrbit key={cycle} />}
    </CelebrationFrame>
  );
}

/** The eight orbiting icons plus the big centre one — `_StreakOrbit`. */
function StreakOrbit() {
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (root === null) return;
    const orbits = [...root.querySelectorAll<HTMLElement>('[data-orbit-index]')];
    const centre = root.querySelector<HTMLElement>('[data-orbit-centre]');
    if (centre === null) return;

    // `LayoutBuilder(constraints)`. `clientWidth/Height` and not
    // `getBoundingClientRect`, because ../widgets/PhoneFrame.tsx scales the
    // whole device with a CSS transform and only the former reports the
    // LAYOUT pixels the Dart constraints are quoted in.
    const layout = orbitLayout(root.clientWidth, root.clientHeight);
    for (const element of orbits) {
      element.style.width = `${String(layout.orbitSize)}px`;
      element.style.height = `${String(layout.orbitSize)}px`;
    }
    centre.style.width = `${String(layout.iconSize)}px`;
    centre.style.height = `${String(layout.iconSize)}px`;

    let raf = 0;
    let startMs = 0;
    const frame = (now: number): void => {
      if (startMs === 0) startMs = now;
      const elapsed = Math.min(now - startMs, ORBIT_TOTAL_MS);
      const f = orbitFrame(elapsed, layout.maxRadius);
      orbits.forEach((element, index) => {
        const { x, y } = orbitOffset(index, f.spin, f.radius);
        element.style.transform = `translate(-50%, -50%) translate(${String(x)}px, ${String(y)}px)`;
        // `Opacity(opacity: opacity.clamp(0, 1))` — Dart reuses the radius
        // factor as the ring's opacity, so the icons fade with the collapse.
        element.style.opacity = String(f.radiusFactor < 0 ? 0 : f.radiusFactor > 1 ? 1 : f.radiusFactor);
      });
      centre.style.transform = `translate(-50%, -50%) scale(${String(f.iconScale)})`;
      centre.style.opacity = String(f.iconOpacity);
      if (elapsed < ORBIT_TOTAL_MS) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => {
      cancelAnimationFrame(raf);
    };
  }, []);

  return (
    // `SizedBox.expand > Stack(alignment: center)`. Everything starts at
    // opacity 0, which is what the driver's own frame 0 resolves to — so the
    // first painted frame is already correct with no transform written yet.
    <div ref={rootRef} className={styles.orbit}>
      {Array.from({ length: ORBIT_COUNT }, (_, index) => (
        <div key={index} className={styles.orbitIcon} data-orbit-index={index} style={{ opacity: 0 }}>
          <StreakIcon />
        </div>
      ))}
      <div className={styles.orbitCentre} data-orbit-centre="" style={{ opacity: 0 }}>
        <StreakIcon />
      </div>
    </div>
  );
}

/** `_image` — the theme's `streak_icon` over the bundled fallback. */
function StreakIcon() {
  return (
    <ThemedImage
      className={styles.streakImg}
      slot={SLOT_STREAK_ICON}
      fallbackSrc={showcaseAsset('streak_icon.png')}
      alt=""
    />
  );
}

/** `_StatsContent` — `Column(min, spacing: spacingLarge)`. */
function StatsContent() {
  return (
    <div className={styles.stats} style={showcaseStyle(STATS_VARS)}>
      {/* `StaggeredReveal` over a `Column(min)` with NO spacing of its own. */}
      <div className={styles.headline}>
        <span className={styles.count}>
          <CountUpText target={WEEK_COUNT} />
        </span>
        <span className={styles.unit}>week streak</span>
      </div>
      {/* `StaggeredReveal(delay: subtitleDelay)` over `p` at `text2nd`. */}
      <p className={styles.subtitle}>{SUBTITLE}</p>
      <StreakWeekStrip days={WEEK_DAYS} baseDelayMs={STRIP_DELAY_MS} />
    </div>
  );
}
