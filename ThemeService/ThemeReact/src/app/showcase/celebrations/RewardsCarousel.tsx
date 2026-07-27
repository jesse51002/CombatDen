// Ports ../../../../../../CRM/lib/showcase/celebrations/rewards_carousel.dart —
// a clone of MobileApp's `RewardsCarousel`: a cover-flow reward strip where the
// active page is full size and face-on and its neighbours shrink and tilt away
// in 3D.
//
// WHAT REPLACES THE `PageController`. Dart hands the carousel a controller and
// the OWNER drives it (`rewards_card_showcase.dart` calls `animateToPage(
// _page + 1, 450ms, easeInOutCubic)` every five seconds). React has no such
// object, so the controller's two jobs split: the owner keeps the integer
// `page` it already had and passes it as a prop, and the TWEEN — the thing the
// controller actually owned — moves in here, where a rAF driver eases the
// fractional page toward the prop and writes each page's transform straight to
// its element. That is faithful in the way that matters: every intermediate
// frame is `coverFlowTransform` of a live fractional offset, exactly as the
// `AnimatedBuilder` recomputes it, rather than a browser's interpolation
// between two already-resolved matrices.
//
// A page's element is placed in a REF CALLBACK as well as by the driver.
// Advancing mounts one new page element at the far edge, and a mount is
// precisely where Dart would reach for `addPostFrameCallback`: the callback
// fires at commit with the node in hand, so the new page is already positioned
// on its first painted frame instead of flashing at the centre.
//
// NO SWIPE. Every showcase surface is a preview inside a phone frame and takes
// no input, which is why there is no scroll container here and why Dart's
// `onPageChanged` has no counterpart — nothing but the owner can change the
// page.

import { useEffect, useRef, useState } from 'react';

import { showcaseAssetOrNetwork } from '../showcaseAssets';
import { showcaseStyle } from '../showcaseTokens';
import { usePrefersReducedMotion } from '../usePrefersReducedMotion';

import { Curves } from './curves';
import styles from './RewardsCarousel.module.css';
import {
  FEATURED_SIZE,
  PERSPECTIVE_PX,
  SLIDE_MS,
  VIEWPORT_FRACTION,
  coverFlowTransform,
  wrapIndex,
} from './rewardsCoverFlow';
import type { ShowcaseRewardItem } from './showcaseCelebrationStats';

/**
 * How many slots either side of the active page are rendered.
 *
 * Dart's `PageView.builder` has no `itemCount` — it is infinite, and Flutter
 * builds only what the viewport needs. Two either side IS that viewport: a page
 * three slots out is off the phone's edge at every scale the cover flow
 * produces, and one advance can only ever pull one new slot into view.
 */
const WINDOW = 2;

/** The attribute the driver finds its page elements by. */
const PAGE_ATTR = 'data-carousel-page';

/**
 * `AnimatedBuilder`'s body for ONE page. Module-level because it closes over
 * nothing: the element carries its own slot number and the maths lives in
 * ./rewardsCoverFlow.ts.
 */
function placePage(element: HTMLElement, fractionalPage: number): void {
  const slot = Number(element.dataset['carouselPage']);
  const offset = slot - fractionalPage;
  const { scale, tiltRadians } = coverFlowTransform(offset);
  // A page slot's own share of the viewport IS its width, so translating by a
  // percentage of itself is translating by whole slots — nothing measured.
  element.style.transform = `translateX(-50%) translateX(${String(offset * 100)}%)`;
  const circle = element.firstElementChild;
  if (circle instanceof HTMLElement) {
    circle.style.transform = `perspective(${String(PERSPECTIVE_PX)}px) rotateY(${String(tiltRadians)}rad) scale(${String(scale)})`;
  }
}

export interface RewardsCarouselProps {
  items: readonly ShowcaseRewardItem[];
  /**
   * The UNBOUNDED page index, exactly Dart's `_page`. The item shown in a slot
   * is `items[slot % items.length]`, so the owner may count up forever.
   */
  page: number;
  /** `_slideDuration` — how long one page advance takes to settle. */
  slideMs?: number | undefined;
  /** `_featuredSize` — the active circle's diameter, in px. */
  featuredSize?: number | undefined;
}

export function RewardsCarousel({
  items,
  page,
  slideMs = SLIDE_MS,
  featuredSize = FEATURED_SIZE,
}: RewardsCarouselProps) {
  const reduceMotion = usePrefersReducedMotion();
  const rootRef = useRef<HTMLDivElement | null>(null);
  /** The live fractional page — the controller's `page`, and the driver's state. */
  const currentPage = useRef(page);

  useEffect(() => {
    const root = rootRef.current;
    if (root === null) return;
    const applyAll = (fractionalPage: number): void => {
      currentPage.current = fractionalPage;
      for (const element of root.querySelectorAll<HTMLElement>(`[${PAGE_ATTR}]`)) {
        placePage(element, fractionalPage);
      }
    };

    const from = currentPage.current;
    // `MediaQuery.disableAnimationsOf`, and the first mount: land, don't tween.
    if (reduceMotion || from === page) {
      applyAll(page);
      return;
    }

    let raf = 0;
    let startMs = 0;
    const frame = (now: number): void => {
      if (startMs === 0) startMs = now;
      const t = Math.min((now - startMs) / slideMs, 1);
      // `controller.animateToPage(..., curve: Curves.easeInOutCubic)`.
      applyAll(from + (page - from) * Curves.easeInOutCubic(t));
      if (t < 1) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => {
      cancelAnimationFrame(raf);
    };
  }, [page, slideMs, reduceMotion]);

  const slots: number[] = [];
  for (let slot = page - WINDOW; slot <= page + WINDOW; slot++) slots.push(slot);

  return (
    <div
      ref={rootRef}
      className={styles.carousel}
      style={showcaseStyle({
        '--rc-size': `${String(featuredSize)}px`,
        '--rc-viewport-fraction': `${String(VIEWPORT_FRACTION * 100)}%`,
      })}
    >
      {slots.map((slot) => {
        const item = items[wrapIndex(slot, items.length)];
        if (item === undefined) return null;
        return (
          <div
            key={slot}
            className={styles.page}
            data-carousel-page={slot}
            ref={(node) => {
              if (node !== null) placePage(node, currentPage.current);
            }}
          >
            <RewardCircle item={item} />
          </div>
        );
      })}
    </div>
  );
}

/**
 * `_RewardCircle` — the gym's own reward photo when the host injected one, else
 * the bundled sample.
 */
function RewardCircle({ item }: { item: ShowcaseRewardItem }) {
  const src = showcaseAssetOrNetwork(item.imageUrl, item.imageAsset);
  // `key` remounts the frame whenever the photo changes, so one dead URL cannot
  // pin the slot to the empty disc forever. The same reset ../home/ClassListItem.tsx
  // and the library's <ThemedImage> use, and for the same reason.
  return <RewardCircleFrame key={src} src={src} alt={item.name} />;
}

/**
 * A photo that fails to load degrades to a flat `card` disc rather than a
 * broken-image box — Dart's `errorBuilder`.
 */
function RewardCircleFrame({ src, alt }: { src: string; alt: string }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className={styles.circle}>
      {!failed && (
        <img
          className={styles.photo}
          src={src}
          alt={alt}
          onError={() => {
            setFailed(true);
          }}
        />
      )}
    </div>
  );
}
