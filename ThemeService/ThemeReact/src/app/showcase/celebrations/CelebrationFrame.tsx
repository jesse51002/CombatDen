// Ports ../../../../../../MobileApp/lib/shared/widgets/post_class/post_class_scaffold.dart
// and the five layouts beside it (post_class/layouts/celebration_*.dart) — the
// frame every post-class celebration card is composed into, and the ONE place
// `celebration_format` is resolved.
//
// ONE ENUM, EVERY CARD. `CelebrationFormat` governs all of them at once — the
// body differs per card, the arrangement around it does not — so the hook lives
// HERE and not in the screens. The cards render this frame and therefore
// rearrange together, without ../showcaseScreen.tsx (the shared registration
// file all of them are registered in) ever learning that the slot exists.
//
// FOUR CARDS HERE, FIVE IN THE MEMBER APP. `MobileApp`'s five
// `PostClassScaffold` consumers are wins / points / rewards / streak / rank; the
// Flutter preview this island ports (`CRM/lib/showcase/`) never carried a rank
// celebration, so there are four to rearrange here: ../WinsShowcase.tsx,
// ../PointsShowcase.tsx, ../RewardsCardShowcase.tsx and ../StatsShowcase.tsx
// (streak). ../BookingShowcase.tsx is NOT one of them — it clones
// `ClassBookedScreen`, a class-detail surface, which is `ClassFormat`'s.
//
// THE INVARIANT: an arrangement changes ARRANGEMENT ONLY. The member app's
// layouts place four slots — header, body, close and exactly one primary action.
// A preview card ships exactly ONE of them, its body, and this frame places
// exactly that one: it never invents an action to arrange, and no value reaches
// data the shipped screen did not already have. `../__tests__/celebrationFormats.test.tsx`
// is the mechanical gate — the stage's subtree must come out byte-identical
// across all five values, per card, in both of each card's views.
//
// WHAT THE ABSENT ACTION LEAVES BEHIND IS A MEASUREMENT, NOT A WIDGET.
// `splitBand` and `fullBleed` are defined by the seam between the celebration
// and the plain canvas the action sits on, so both keep that band of canvas
// clear (`kCelebrationCtaZone`) and the preview keeps the real screen's
// proportions — the same reason ../BookingShowcase.tsx honours the member app's
// own `_kCelebrationMaxHeight`.
//
// NOTHING HERE SCROLLS, and no value may make it. These are the surfaces that
// paint outside their boxes on purpose (./SparkleBurst.tsx, ./RewardsCarousel.tsx's
// cover flow), and `overflow-y: auto` computes `overflow-x` to `auto`, which
// would crop every one of them (../../../CLAUDE.md, "Things that will bite").

import type { ReactNode } from 'react';

import { cx } from '../cx';
import type { CelebrationFormat } from '../formats';
import { CELEBRATION_FORMATS, FORMAT_SLOTS, useFormat } from '../formats';
import { SC, showcaseStyle } from '../showcaseTokens';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';

import styles from './CelebrationFrame.module.css';

/**
 * `AppPrimaryButton`'s own rendered height. Pure layout arithmetic with no
 * `ShowcaseTokens` equivalent — a button's intrinsic height is not a design
 * token — which is why `celebration_scrim.dart` keeps it as a `_k` constant
 * rather than a literal at the call site, and why this mirrors it.
 */
const CTA_HEIGHT = 48;

/**
 * `kCelebrationCtaZone` — the height `splitBand` and `fullBleed` keep clear
 * beneath the celebration: the action's own height plus the gap above it and
 * the inset below it.
 *
 * These preview cards ship no action, so nothing is drawn in it. It is kept
 * anyway because it is what makes those two arrangements read as themselves:
 * both are a seam between the celebration and the canvas the action stands on,
 * and a preview that closed the gap would be showing proportions the member app
 * does not have.
 */
export const CELEBRATION_LOWER_ZONE = CTA_HEIGHT + SC.spacingBig * 2;

/** `CelebrationScrim._kHeight` — one `spacingBig` of overlap onto the stage. */
export const CELEBRATION_SCRIM_HEIGHT = CELEBRATION_LOWER_ZONE + SC.spacingBig;

/**
 * The geometry the stylesheet reads. Theme-independent, so a module constant:
 * both values are arithmetic over `ShowcaseTokens`, and neither is restated as
 * a literal in the `.module.css`.
 */
const FRAME_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--cf-lower-zone': `${String(CELEBRATION_LOWER_ZONE)}px`,
  '--cf-scrim-height': `${String(CELEBRATION_SCRIM_HEIGHT)}px`,
});

/** One arrangement's class — `PostClassScaffold._build`'s switch. */
function arrangementClass(format: CelebrationFormat): string | undefined {
  switch (format) {
    case 'centerHero':
      return styles.centerHero;
    case 'figureTop':
      return styles.figureTop;
    case 'cardReveal':
      return styles.cardReveal;
    case 'splitBand':
      return styles.splitBand;
    case 'fullBleed':
      return styles.fullBleed;
  }
}

export interface CelebrationFrameProps {
  /** The card's own content — one opaque block, exactly as `CelebrationData.body` is. */
  children: ReactNode;
  /**
   * The body takes the stage's whole box with no breathing room of its own.
   *
   * ONE BRANCH PASSES THIS: ../StatsShowcase.tsx's orbit, which ships as a bare
   * `SizedBox.expand` while its sibling views sit inside a
   * `Padding(vertical: spacingBig)` (`CRM/lib/showcase/stats_showcase.dart:95`).
   * The member app has no such split — there the layout insets every body — so
   * this is the Flutter PREVIEW's own quirk, carried through unchanged because
   * `centerHero` must render exactly what ships today.
   */
  bleed?: boolean;
}

/**
 * The tenant's arrangement, resolved once and applied to whichever card is
 * rendering. The three parts mirror the layouts one for one: a frame that owns
 * the screen insets, a surface that is the raised object `cardReveal` and
 * `splitBand` paint (and nothing at all in the other three), and the stage the
 * body settles in — `CelebrationStage`'s `Align`, minus the tap-to-skip target,
 * which has no counterpart on a preview card that never had a CTA to unblock.
 */
export function CelebrationFrame({ children, bleed = false }: CelebrationFrameProps) {
  const format = useFormat(FORMAT_SLOTS.celebration, CELEBRATION_FORMATS, 'centerHero');

  return (
    // `AppScreenScaffold(horizontalPadding: none)` — every layout owns its own
    // insets, because `splitBand` and `fullBleed` need the canvas edge and
    // `centerHero` re-applies the standard screen padding so it renders exactly
    // as it always has.
    <ShowcaseScaffold horizontalPadding="none">
      <div
        className={cx(styles.frame, arrangementClass(format))}
        style={showcaseStyle(FRAME_VARS)}
        data-celebration-format={format}
      >
        <div className={styles.surface}>
          <div className={cx(styles.stage, bleed && styles.bleed)}>{children}</div>
        </div>
        {/* `CelebrationScrim` — `fullBleed`'s only extra part. */}
        {format === 'fullBleed' && <div className={styles.scrim} aria-hidden="true" />}
      </div>
    </ShowcaseScaffold>
  );
}
