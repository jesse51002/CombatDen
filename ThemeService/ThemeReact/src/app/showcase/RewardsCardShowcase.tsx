// Ports ../../../../../CRM/lib/showcase/rewards_card_showcase.dart — an exact
// visual clone of the member app's post-class "REWARDS YOU CAN GET"
// celebration (`RewardsScreen` / `RewardsBody`): a giftbox flies in with a 3D
// spin, bursts into a radial scatter of `single_point` stars, then the title,
// subtitle, auto-advancing cover-flow carousel and featured caption take the
// screen (the points line pulses once per advance). It loops.
//
// NOT to be confused with ./RewardsShowcase.tsx, which ports
// `rewards_showcase.dart` — the static Points STORE. The two Dart files are
// named that way and the ports keep their names, because a reviewer runs the
// two side by side.
//
// TWO VIEWS, ONE SWITCH, the same shape as ./StatsShowcase.tsx and
// ./PointsShowcase.tsx: the intro runs its own timeline, hands over to the
// carousel, which holds for `_kCarouselHold` before the whole thing restarts
// with a bumped `_cycle`. One 5s idle beat fits inside that hold, so exactly
// one page advance happens per loop — which is the Dart's own cadence, not a
// simplification.
//
// WHAT REPLACES `didUpdateWidget`. Dart rebuilds its stats and paging in place
// when the injected rewards change. Resetting state from an effect is a lint
// error in this package (../../CLAUDE.md), so the celebration is `key`-remounted
// on a signature of the resolved items instead — the sanctioned replacement,
// and the same reset ../home/classItem/ClassItemThumb.tsx uses for a changed photo.
//
// WHAT DRIVES WHAT. The giftbox intro is the one rAF driver: the box's spin and
// fourteen stars share ONE clock and are recomputed per frame (./rewardsCelebration.ts
// holds that arithmetic). The carousel owns its own tween
// (./celebrations/RewardsCarousel.tsx). Everything else — the title and
// subtitle reveals, the caption's switch, the points pulse — is a CSS keyframe.

import { useEffect, useRef, useState } from 'react';
import { CelebrationTimings, EASE_OUT_QUART, ThemedImage } from 'theme-react';

import { CelebrationFrame } from './celebrations/CelebrationFrame';
import { RewardsCarousel } from './celebrations/RewardsCarousel';
import { cx } from './cx';
import { SLIDE_MS, wrapIndex } from './celebrations/rewardsCoverFlow';
import type { ShowcaseRewardsStats } from './celebrations/showcaseCelebrationStats';
import { formatThousands } from './formatPoints';
import {
  BOX_PERSPECTIVE_PX,
  BOX_SIZE,
  BURST_SEEDS,
  CAROUSEL_HOLD_MS,
  IDLE_MS,
  INTRO_TOTAL_MS,
  PULSE_DECAY_EASE,
  PULSE_MS,
  PULSE_PEAK_SCALE,
  boxFrame,
  buildRewardsStats,
  burstMaxRadius,
  burstProgress,
  burstStarFrame,
  initialPage,
  rewardsSignature,
} from './rewardsCelebration';
import styles from './RewardsCardShowcase.module.css';
import { showcaseAsset } from './showcaseAssets';
import type { ShowcaseReward } from './showcaseContent';
import { SLOT_GIFTBOX, SLOT_SINGLE_POINT } from './showcaseSlots';
import { showcaseStyle } from './showcaseTokens';
import { usePrefersReducedMotion } from './usePrefersReducedMotion';

/** `subtitleDelay` — one standard stagger after the title. */
export const SUBTITLE_DELAY_MS = CelebrationTimings.revealStaggerMs;
/** `carouselDelay` — the carousel starts once the subtitle's reveal has LANDED. */
export const CAROUSEL_DELAY_MS = SUBTITLE_DELAY_MS + CelebrationTimings.revealMs;

/** `StaggeredReveal.offset` — the slide a reveal travels, in px. */
const REVEAL_OFFSET_PX = 12;

/** The motion values the stylesheet reads. Theme-independent. */
const REWARDS_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--rw-box-size': `${String(BOX_SIZE)}px`,
  '--rw-perspective': `${String(BOX_PERSPECTIVE_PX)}px`,
  '--rw-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
  '--rw-reveal-offset': `${String(REVEAL_OFFSET_PX)}px`,
  '--rw-subtitle-delay-ms': `${String(SUBTITLE_DELAY_MS)}ms`,
  '--rw-carousel-delay-ms': `${String(CAROUSEL_DELAY_MS)}ms`,
  '--rw-switch-ms': `${String(SLIDE_MS)}ms`,
  '--rw-pulse-ms': `${String(PULSE_MS)}ms`,
  '--rw-pulse-peak': String(PULSE_PEAK_SCALE),
  '--rw-pulse-decay-ease': PULSE_DECAY_EASE,
  '--rw-ease': EASE_OUT_QUART,
});

/** The attributes the intro's driver finds its elements by. */
const BOX_ATTR = 'data-giftbox';
const BURST_ATTR = 'data-burst-index';

export interface RewardsCardShowcaseProps {
  loop?: boolean;
  onCycleComplete?: (() => void) | undefined;
  /**
   * The previewed gym's rewards. Non-empty shows them (with their network
   * photos) instead of the bundled sample set — `RewardsCardShowcase.rewards`.
   */
  rewards?: readonly ShowcaseReward[] | null;
}

export function RewardsCardShowcase({
  loop = true,
  onCycleComplete,
  rewards,
}: RewardsCardShowcaseProps) {
  const stats = buildRewardsStats(rewards);
  return (
    <RewardsCelebration
      key={rewardsSignature(stats)}
      stats={stats}
      loop={loop}
      onCycleComplete={onCycleComplete}
    />
  );
}

interface RewardsCelebrationProps {
  stats: ShowcaseRewardsStats;
  loop: boolean;
  onCycleComplete?: (() => void) | undefined;
}

/** `_RewardsCardShowcaseState` — the cycle, the paging and the two views. */
function RewardsCelebration({ stats, loop, onCycleComplete }: RewardsCelebrationProps) {
  const reduceMotion = usePrefersReducedMotion();
  const firstPage = initialPage(stats.items.length, stats.featuredIndex);
  const [cycle, setCycle] = useState(0);
  const [showCarousel, setShowCarousel] = useState(false);
  /** `_page` — UNBOUNDED, exactly as in Dart. The item is `page % length`. */
  const [page, setPage] = useState(firstPage);

  useEffect(() => {
    if (reduceMotion) return;
    // `_ctrl.forward().whenComplete(widget.onComplete)` → `_onIntroDone`.
    const toCarousel = window.setTimeout(() => {
      setShowCarousel(true);
    }, INTRO_TOTAL_MS);
    // `_holdTimer = Timer(_kCarouselHold, _restart)`, armed by `_onIntroDone`.
    // Collapsed into one absolute deadline so the pair re-arms as a unit.
    const restart = window.setTimeout(() => {
      onCycleComplete?.();
      if (!loop) return;
      setShowCarousel(false);
      // `_resetPaging()` — back to the featured item for the next cycle.
      setPage(firstPage);
      setCycle((current) => current + 1);
    }, INTRO_TOTAL_MS + CAROUSEL_HOLD_MS);
    return () => {
      window.clearTimeout(toCarousel);
      window.clearTimeout(restart);
    };
  }, [cycle, loop, reduceMotion, onCycleComplete, firstPage]);

  // `_scheduleNext` / `_advance`. Dart arms the first advance the moment the
  // intro ends, but re-arms subsequent ones only after `animateToPage`'s future
  // has RESOLVED — so every advance after the first is a slide plus an idle.
  const advanceDelayMs = page === firstPage ? IDLE_MS : SLIDE_MS + IDLE_MS;

  useEffect(() => {
    if (!showCarousel || reduceMotion) return;
    const advance = window.setTimeout(() => {
      setPage((current) => current + 1);
    }, advanceDelayMs);
    return () => {
      window.clearTimeout(advance);
    };
  }, [showCarousel, page, advanceDelayMs, reduceMotion]);

  // Reduced motion goes straight to the carousel: the giftbox intro is pure
  // motion, so there is no "end state" of it worth rendering.
  return (
    // The celebration's arrangement — `PostClassScaffold`, resolved from the
    // tenant's `celebration_format` (./celebrations/CelebrationFrame.tsx). It
    // frames BOTH views, exactly as the `Padding(vertical: spacingBig) > Center`
    // it replaces did; `REWARDS_VARS` therefore rides each view's own root,
    // where the rest of this island already puts its motion variables.
    <CelebrationFrame>
      {showCarousel || reduceMotion ? (
        <CarouselLayout stats={stats} page={page} switched={page !== firstPage} />
      ) : (
        <GiftboxIntro key={cycle} />
      )}
    </CelebrationFrame>
  );
}

/** `_CarouselLayout` — `Column(min, stretch, spacing: spacingBig)`. */
function CarouselLayout({
  stats,
  page,
  switched,
}: {
  stats: ShowcaseRewardsStats;
  page: number;
  switched: boolean;
}) {
  const featuredIndex = wrapIndex(page, stats.items.length);
  const featured = stats.items[featuredIndex];

  return (
    <div className={styles.carouselLayout} style={showcaseStyle(REWARDS_VARS)}>
      {/* `Column(min, spacing: spacingMedium)` — both lines are reveals. */}
      <div className={styles.headings}>
        <p className={styles.title}>{stats.title}</p>
        <p className={styles.subtitle}>{stats.subtitle}</p>
      </div>

      {/* `StaggeredReveal(delay: carouselDelay, offset: 0)` — a pure fade. */}
      <div className={styles.carouselSlot}>
        <RewardsCarousel items={stats.items} page={page} />
      </div>

      {/*
        `AnimatedSwitcher(duration: slideDuration, child: Column(key: featuredIndex))`.
        The key remount is the switch; the fade is the CSS below, and it is armed
        only once a page has actually changed — `AnimatedSwitcher` adds its FIRST
        child with `animate: false`.

        ONE DEVIATION, and it is structural: React unmounts the outgoing caption
        immediately, so this is a fade-IN rather than the Dart's cross-fade.
        Keeping the old node alive to fade it out would mean tracking the
        previous featured item in state purely for a 450ms decoration.
      */}
      {featured !== undefined && (
        <div
          key={featuredIndex}
          className={cx(styles.featured, switched && styles.featuredSwitch)}
        >
          <p className={styles.featuredName}>{featured.name}</p>
          <p className={styles.featuredDiscount}>{featured.discountLabel}</p>
          {/* `_PulsePoints` — one-shot bell pulse, re-fired by the key remount. */}
          <p className={styles.featuredPoints}>{formatThousands(featured.pointsCost)} pts</p>
        </div>
      )}
    </div>
  );
}

/** `_GiftboxIntro` — entrance, hold, burst. One clock, one rAF driver. */
function GiftboxIntro() {
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (root === null) return;
    const box = root.querySelector<HTMLElement>(`[${BOX_ATTR}]`);
    const stars = [...root.querySelectorAll<HTMLElement>(`[${BURST_ATTR}]`)];
    if (box === null) return;

    // `LayoutBuilder(constraints)`. `clientWidth/Height` and not
    // `getBoundingClientRect`, because ../widgets/PhoneFrame.tsx scales the
    // whole device with a CSS transform and only the former reports the LAYOUT
    // pixels the Dart constraints are quoted in.
    const maxRadius = burstMaxRadius(root.clientWidth, root.clientHeight);

    let raf = 0;
    let startMs = 0;
    const frame = (now: number): void => {
      if (startMs === 0) startMs = now;
      const elapsed = Math.min(now - startMs, INTRO_TOTAL_MS);

      const boxValues = boxFrame(elapsed);
      // `Matrix4..setEntry(3, 2, 0.001)..rotateY(y)..scale(s)` with
      // `alignment: center` — the perspective's vanishing point is the box's
      // own centre, which is what `transform-origin: center` gives CSS.
      box.style.transform = `translate(-50%, -50%) perspective(${String(BOX_PERSPECTIVE_PX)}px) rotateY(${String(boxValues.yRotationRadians)}rad) scale(${String(boxValues.scale)})`;
      box.style.opacity = String(boxValues.opacity);

      const burstT = burstProgress(elapsed);
      stars.forEach((element, index) => {
        const seed = BURST_SEEDS[index];
        if (seed === undefined) return;
        const star = burstStarFrame(seed, burstT, maxRadius);
        element.style.transform = `translate(-50%, -50%) translate(${String(star.dx)}px, ${String(star.dy)}px) scale(${String(star.scale)})`;
        element.style.opacity = String(star.opacity);
      });

      if (elapsed < INTRO_TOTAL_MS) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => {
      cancelAnimationFrame(raf);
    };
  }, []);

  return (
    // `SizedBox.expand > Stack(alignment: center)`, with the box painted OVER
    // the stars exactly as Dart orders them. Everything starts invisible, which
    // is what the driver's own frame 0 resolves to.
    <div ref={rootRef} className={styles.stage} style={showcaseStyle(REWARDS_VARS)}>
      {BURST_SEEDS.map((seed, index) => (
        <div
          key={index}
          className={styles.burstStar}
          data-burst-index={index}
          style={{ width: `${String(seed.size)}px`, height: `${String(seed.size)}px`, opacity: 0 }}
        >
          <ThemedImage
            className={styles.burstStarImg}
            slot={SLOT_SINGLE_POINT}
            fallbackSrc={showcaseAsset('single_point.png')}
            alt=""
          />
        </div>
      ))}
      <div className={styles.giftbox} data-giftbox="" style={{ opacity: 0 }}>
        <ThemedImage
          className={styles.giftboxImg}
          slot={SLOT_GIFTBOX}
          fallbackSrc={showcaseAsset('giftbox.png')}
          alt=""
        />
      </div>
    </div>
  );
}
