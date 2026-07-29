// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// member_app/theme_tab/theme_preview_pane.dart.
//
// The left pane: a large phone mockup that fills the available space, showing
// the active showcase screen (re-themed live), with prev/next arrows and a
// tappable view list beneath it.
//
// WHAT IS DELIBERATELY NOT PORTED — the two admin-only actions under the mock.
// `SetAppThemeButton` persists the previewed theme as a gym's app branding and
// the "Edit gym name / logo" button opens `GymProfileDialog`; both are guarded
// in Dart by `selectedGym.gymId != null`, and this browser is the public,
// unauthenticated surface where that is ALWAYS null. There is no gym, no
// Supabase session and no write endpoint here, so neither button has anything
// to do. The gym name / logo the Dart pane threads into the mock go with them:
// with no gym, the showcase falls through to the ACTIVE THEME's own identity,
// which is what the public branch already did.
//
// DEVIATION — the slide index lives HERE, not in the host. Dart keeps `_slide`
// / `_forward` in `_LiveThemePreviewTabState` and passes them down, because
// `AnimatedSwitcher` tracks the outgoing child itself. React has no such
// built-in, so the outgoing screen has to be held in state — and deriving that
// from a changing prop would mean adjusting state during render or resetting it
// in an effect, both of which this package's lint gate forbids (see
// ../../../CLAUDE.md). Owning the whole transition in one state object updated
// from the click handlers is the lint-clean equivalent, and it makes the pane
// self-contained.

import { useState } from 'react';
import { useActiveDesign } from 'theme-react';

import { SHOWCASE_SCREENS, SHOWCASE_SCREEN_LABELS, ShowcaseScreenView } from '../showcase/showcaseScreen';
import { ChevronLeftIcon, ChevronRightIcon } from '../widgets/icons';
import { cx } from '../widgets/cx';
import { PhoneFrame } from '../widgets/PhoneFrame';
import { usePrefersReducedMotion } from '../widgets/usePrefersReducedMotion';

import { useSelectedStyle } from './selectedStyle';

import styles from './ThemePreviewPane.module.css';

interface SlideState {
  /** The screen on show. */
  readonly index: number;
  /** The screen sliding out, or `null` once the transition has settled. */
  readonly from: number | null;
  /** Direction: a forward move slides the new screen in from the right. */
  readonly forward: boolean;
  /** Bumped per move, so a re-entered direction still restarts the animation. */
  readonly seq: number;
}

const SETTLED: SlideState = { index: 0, from: null, forward: true, seq: 0 };

export function ThemePreviewPane() {
  const [slide, setSlide] = useState<SlideState>(SETTLED);
  const reduceMotion = usePrefersReducedMotion();
  const { id: activeDesignId } = useActiveDesign();
  // The picked style's category selects which bundled/fetched demo content the
  // phone shows, so a Yoga theme previews yoga classes rather than boxing.
  // It lives out here because the showcase island may not import from
  // `browser/` (lint Gate 2a) — the seam is the `category` prop.
  const { category } = useSelectedStyle();

  const count = SHOWCASE_SCREENS.length;
  const screen = SHOWCASE_SCREENS[slide.index] ?? SHOWCASE_SCREENS[0]!;
  const outgoing = slide.from === null ? null : (SHOWCASE_SCREENS[slide.from] ?? null);

  const go = (next: number, forward: boolean) => {
    setSlide((current) => ({
      index: next,
      // Under reduced motion nothing animates, so nothing would ever emit the
      // `animationend` that clears the outgoing pane — it is never mounted.
      from: reduceMotion ? null : current.index,
      forward,
      seq: current.seq + 1,
    }));
  };

  const onPrev = () => go((slide.index - 1 + count) % count, false);
  const onNext = () => go((slide.index + 1) % count, true);
  const onSelect = (i: number) => {
    if (i === slide.index) return;
    go(i, i >= slide.index);
  };

  /** The exiting pane has finished; drop it. */
  const settle = () => setSlide((current) => (current.from === null ? current : { ...current, from: null }));

  return (
    <div className={styles.pane}>
      <div className={styles.phoneWrap}>
        <PhoneFrame>
          <div className={styles.stage}>
            {outgoing !== null && (
              <div
                key={`${slide.seq}-out`}
                className={cx(styles.slide, slide.forward ? styles.exitLeft : styles.exitRight)}
                onAnimationEnd={settle}
              >
                <ShowcaseScreenView screen={outgoing} category={category} />
              </div>
            )}
            <div
              // Restart the showcase's own animation on a theme change; the
              // slide itself is driven by `seq`, so a re-theme never slides.
              key={`${activeDesignId ?? ''}-${screen}-${slide.seq}`}
              className={cx(
                styles.slide,
                outgoing !== null && (slide.forward ? styles.enterRight : styles.enterLeft),
              )}
            >
              <ShowcaseScreenView screen={screen} category={category} />
            </div>
          </div>
        </PhoneFrame>
      </div>

      <div className={styles.controls}>
        <button type="button" className={styles.arrow} aria-label="Previous view" onClick={onPrev}>
          <ChevronLeftIcon size={24} />
        </button>
        <div className={styles.chips}>
          {SHOWCASE_SCREENS.map((value, i) => (
            <button
              key={value}
              type="button"
              className={cx(styles.chip, i === slide.index && styles.chipActive)}
              aria-pressed={i === slide.index}
              onClick={() => onSelect(i)}
            >
              {SHOWCASE_SCREEN_LABELS[value]}
            </button>
          ))}
        </div>
        <button type="button" className={styles.arrow} aria-label="Next view" onClick={onNext}>
          <ChevronRightIcon size={24} />
        </button>
      </div>
    </div>
  );
}
