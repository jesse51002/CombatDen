// Ports ../../../../../CRM/lib/showcase/points_showcase.dart — an exact visual
// clone of the member app's post-class POINTS celebration (`PointsScreen` /
// `PointsBody`): fourteen `single_point` stars distributed on a sphere fill the
// body, spin, then collapse inward to nothing — and the focused stat
// illustration, a "+N points" count-up and the all-time total caption cascade
// in behind them. It loops.
//
// TWO VIEWS, ONE SWITCH — the same shape as `_PointsShowcaseState`, and as
// ./StatsShowcase.tsx: the sphere runs its own timeline, hands over to the
// focused statement, which holds for `_kPointsHold` before the whole thing
// restarts with a bumped `_cycle`. The cycle re-keys the sphere, which is what
// makes it replay; here it also re-keys the statement so its CSS entrances
// replay with it.
//
// WHY THE SPHERE IS THE ONE rAF DRIVER IN THIS SCREEN. Every other entrance is
// one element tweening between fixed endpoints, which is a keyframe. The swarm
// is not: fourteen stars share ONE spin angle and ONE converge factor, and each
// one's position is that angle projected through its own seed — a value that
// has to be recomputed per frame. So the driver writes `transform`, `opacity`
// and `z-index` straight to the elements' refs and never through React state:
// fourteen particles at 60fps must not cost fourteen re-renders. The maths
// itself is in ./pointSphere.ts, where it can be asserted.
//
// The focused half needs none of that and gets none: the count-up drives itself
// (./celebrations/CountUpText.tsx) and the two reveals are CSS.

import { useEffect, useRef, useState } from 'react';
import { CelebrationTimings, EASE_OUT_QUART, ThemedImage } from 'theme-react';

import { CelebrationFrame } from './celebrations/CelebrationFrame';
import { CountUpText } from './celebrations/CountUpText';
import { SHOWCASE_POINTS_STATS } from './celebrations/showcaseCelebrationStats';
import { formatThousands } from './formatPoints';
import { HERO_SIZE, POINTS_HOLD_MS, SPHERE_MS, STAR_SEEDS, sphereFrame, sphereLayout, starSize } from './pointSphere';
import styles from './PointsShowcase.module.css';
import { showcaseAsset } from './showcaseAssets';
import { SLOT_POINTS_STARS_IMAGE, SLOT_SINGLE_POINT } from './showcaseSlots';
import { showcaseStyle } from './showcaseTokens';
import { usePrefersReducedMotion } from './usePrefersReducedMotion';

/**
 * `_TotalCaption`'s `StaggeredReveal(delay: countUpDuration + revealStagger)` —
 * the caption waits out the whole count-up roll plus one standard stagger.
 */
export const TOTAL_DELAY_MS = CelebrationTimings.countUpMs + CelebrationTimings.revealStaggerMs;

/** `StaggeredReveal.offset` — the slide a reveal travels, in px. */
const REVEAL_OFFSET_PX = 12;

/** The motion values the stylesheet reads. Theme-independent. */
const POINTS_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--pt-hero-size': `${String(HERO_SIZE)}px`,
  '--pt-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
  '--pt-reveal-offset': `${String(REVEAL_OFFSET_PX)}px`,
  '--pt-total-delay-ms': `${String(TOTAL_DELAY_MS)}ms`,
  '--pt-ease': EASE_OUT_QUART,
});

/** The attribute the driver finds its star elements by. */
const STAR_ATTR = 'data-star-index';

export interface PointsShowcaseProps {
  loop?: boolean;
  onCycleComplete?: (() => void) | undefined;
}

export function PointsShowcase({ loop = true, onCycleComplete }: PointsShowcaseProps) {
  const reduceMotion = usePrefersReducedMotion();
  const [cycle, setCycle] = useState(0);
  const [showPoints, setShowPoints] = useState(false);

  useEffect(() => {
    if (reduceMotion) return;
    // `_ctrl.forward().whenComplete(widget.onComplete)` → `_onSphereDone`.
    const toPoints = window.setTimeout(() => {
      setShowPoints(true);
    }, SPHERE_MS);
    // `_hold = Timer(_kPointsHold, _restart)`, armed by `_onSphereDone`.
    // Collapsed into one absolute deadline here so the pair re-arms as a unit
    // each cycle.
    const restart = window.setTimeout(() => {
      onCycleComplete?.();
      if (!loop) return;
      setShowPoints(false);
      setCycle((current) => current + 1);
    }, SPHERE_MS + POINTS_HOLD_MS);
    return () => {
      window.clearTimeout(toPoints);
      window.clearTimeout(restart);
    };
    // `cycle` is the dependency that re-arms the pair: the restart bumps it, the
    // effect tears down and re-runs, and the sphere below remounts on its key.
  }, [cycle, loop, reduceMotion, onCycleComplete]);

  // Reduced motion goes straight to the finished statement: the sphere is pure
  // motion, so there is no "end state" of it worth rendering.
  return (
    // The celebration's arrangement — `PostClassScaffold`, resolved from the
    // tenant's `celebration_format` (./celebrations/CelebrationFrame.tsx). It
    // frames BOTH branches on this screen, exactly as the `Padding(vertical:
    // spacingBig)` it replaces did (points_showcase.dart:77).
    <CelebrationFrame>
      {showPoints || reduceMotion ? <FocusedView key={cycle} /> : <PointSphere key={cycle} />}
    </CelebrationFrame>
  );
}

/** The swarm — `_PointSphere`. */
function PointSphere() {
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (root === null) return;
    const stars = [...root.querySelectorAll<HTMLElement>(`[${STAR_ATTR}]`)];

    // `LayoutBuilder(constraints)`. `clientWidth/Height` and not
    // `getBoundingClientRect`, because ../widgets/PhoneFrame.tsx scales the
    // whole device with a CSS transform and only the former reports the LAYOUT
    // pixels the Dart constraints are quoted in.
    const layout = sphereLayout(root.clientWidth, root.clientHeight);
    stars.forEach((element, index) => {
      const size = `${String(starSize(index, layout.renderScale))}px`;
      element.style.width = size;
      element.style.height = size;
    });

    let raf = 0;
    let startMs = 0;
    const frame = (now: number): void => {
      if (startMs === 0) startMs = now;
      const elapsed = Math.min(now - startMs, SPHERE_MS);
      for (const star of sphereFrame(elapsed, layout)) {
        const element = stars[star.index];
        if (element === undefined) continue;
        // Dart nests `Transform.translate > Opacity > Transform.scale`: centre
        // on the stack, move onto the ellipsoid, then scale about the star's
        // OWN centre. The three collapse into one declaration in that order.
        element.style.transform = `translate(-50%, -50%) translate(${String(star.dx)}px, ${String(star.dy)}px) scale(${String(star.scale)})`;
        element.style.opacity = String(star.opacity);
        // The depth sort. Dart reorders the `Stack`'s children; the DOM keeps
        // its order and stacks by `z-index` instead, which is the same paint
        // order without re-parenting fourteen nodes every frame.
        element.style.zIndex = String(star.order);
      }
      if (elapsed < SPHERE_MS) raf = requestAnimationFrame(frame);
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
    <div ref={rootRef} className={styles.sphere}>
      {STAR_SEEDS.map((_, index) => (
        <div key={index} className={styles.star} data-star-index={index} style={{ opacity: 0 }}>
          <PointStar />
        </div>
      ))}
    </div>
  );
}

/** The theme's `single_point` over the bundled fallback. */
function PointStar() {
  return (
    <ThemedImage
      className={styles.starImg}
      slot={SLOT_SINGLE_POINT}
      fallbackSrc={showcaseAsset('single_point.png')}
      alt=""
    />
  );
}

/**
 * The statement the sphere hands over to — `Column(center)` with a `Spacer`
 * either side of the focused content, so it sits centred while the caption is
 * pinned to the bottom.
 */
function FocusedView() {
  const stats = SHOWCASE_POINTS_STATS;
  return (
    <div className={styles.points} style={showcaseStyle(POINTS_VARS)}>
      <div className={styles.spacer} />
      {/* `_FocusedContent` — `StaggeredReveal > Column(min, spacing: spacingLarge)`. */}
      <div className={styles.focused}>
        <ThemedImage
          className={styles.hero}
          slot={SLOT_POINTS_STARS_IMAGE}
          fallbackSrc={showcaseAsset('stat_points_stars.png')}
          alt=""
        />
        <span className={styles.gained}>
          <CountUpText target={stats.gained} prefix="+" suffix=" points" />
        </span>
      </div>
      <div className={styles.spacer} />
      {/* `_TotalCaption` — `StaggeredReveal(delay)` over `h3` at `text2nd`. */}
      <p className={styles.total}>{formatThousands(stats.totalPoints)} total points</p>
    </div>
  );
}
