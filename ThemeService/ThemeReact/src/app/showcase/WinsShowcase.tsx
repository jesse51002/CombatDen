// Ports ../../../../../CRM/lib/showcase/wins_showcase.dart — an exact visual
// clone of the member app's post-class "Today's wins" RECAP (`WinsScreen` /
// `WinsBody`): a trophy hero with a one-shot sparkle burst, the title and
// subtitle cascading under it, and the three info tiles arriving left to right.
// It loops.
//
// THE ARITHMETIC, not the derived numbers (wins_showcase.dart:92-95):
//
//   headerDelay   = revealStagger (90ms)          when the title starts
//   subtitleDelay = headerDelay + revealStagger    one beat later
//   tileBaseDelay = subtitleDelay + reveal(260ms)  after the subtitle has LANDED
//
// Every term is a `CelebrationTimings` value, so the cascade is derived here
// exactly as it is there rather than restated as milliseconds.
//
// HOW IT ANIMATES. Dart wraps each element in a `StaggeredReveal`, which is one
// `AnimationController` per element for a fade-and-slide between fixed
// endpoints — a CSS keyframe with an `animation-delay`, so none of it needs JS.
// The only JS is the loop: one interval bumping a counter that re-keys the
// body, which is exactly what `_cycle` does in Dart and what makes the CSS
// animations replay. The count-up inside a tile is the one driver-backed
// motion; see ./celebrations/CountUpText.tsx for why.
//
// TWO DART CONSTANTS ARE DEAD ON ARRIVAL, and are named here rather than
// copied. `_kHeroBoxWidth` (320) never applies: the content Column is
// `crossAxisAlignment: stretch`, which hands every child TIGHT cross
// constraints of the body's full width, so the hero `SizedBox` renders 358 wide
// on a 390pt device — hence `width: 100%`. `_kSparkleSize` (320) is likewise
// overridden, because the burst is wrapped in a `Positioned.fill` and takes the
// stack's size; the port fills the same way and passes no size at all.

import { useEffect, useState } from 'react';
import { CelebrationTimings, EASE_OUT_QUART, ThemedImage, useThemeText } from 'theme-react';

import { CelebrationFrame } from './celebrations/CelebrationFrame';
import { SparkleBurst } from './celebrations/SparkleBurst';
import { SHOWCASE_WINS_STATS } from './celebrations/showcaseCelebrationStats';
import { WinsTileRow } from './celebrations/WinsTileRow';
import { showcaseAsset } from './showcaseAssets';
import { SLOT_TROPHY_IMAGE, SLOT_WINS_SUBTITLE, SLOT_WINS_TITLE } from './showcaseSlots';
import { showcaseStyle } from './showcaseTokens';
import { usePrefersReducedMotion } from './usePrefersReducedMotion';
import styles from './WinsShowcase.module.css';

/** `_kHeroBoxHeight` — the hero stack the sparkles and the trophy share. */
const HERO_HEIGHT = 280;

/** `_kTrophySize`. */
const TROPHY_SIZE = 230;

/** `_kWinsHold` — how long the finished recap holds before the celebration replays. */
export const WINS_HOLD_MS = 3200;

/** `headerDelay`. */
export const HEADER_DELAY_MS = CelebrationTimings.revealStaggerMs;
/** `subtitleDelay`. */
export const SUBTITLE_DELAY_MS = HEADER_DELAY_MS + CelebrationTimings.revealStaggerMs;
/** `tileBaseDelay` — the tiles start once the subtitle's reveal has finished. */
export const TILE_BASE_DELAY_MS = SUBTITLE_DELAY_MS + CelebrationTimings.revealMs;

/** `StaggeredReveal.offset` — the slide a reveal travels, in px. */
const REVEAL_OFFSET_PX = 12;

/**
 * The motion values the stylesheet reads. Derived from the constants above and
 * from the library's ported motion vocabulary; a module constant, because none
 * of it depends on the theme or on a render.
 */
const MOTION_VARS: Readonly<Record<string, string>> = Object.freeze({
  '--wn-hero-height': `${String(HERO_HEIGHT)}px`,
  '--wn-trophy-size': `${String(TROPHY_SIZE)}px`,
  '--wn-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
  '--wn-reveal-offset': `${String(REVEAL_OFFSET_PX)}px`,
  '--wn-header-delay-ms': `${String(HEADER_DELAY_MS)}ms`,
  '--wn-subtitle-delay-ms': `${String(SUBTITLE_DELAY_MS)}ms`,
  '--wn-ease': EASE_OUT_QUART,
});

export interface WinsShowcaseProps {
  loop?: boolean;
  onCycleComplete?: (() => void) | undefined;
}

export function WinsShowcase({ loop = true, onCycleComplete }: WinsShowcaseProps) {
  const reduceMotion = usePrefersReducedMotion();
  // Re-keys the body so every CSS entrance replays — Dart's `_cycle`.
  const [cycle, setCycle] = useState(0);

  useEffect(() => {
    if (!loop || reduceMotion) return;
    const id = window.setInterval(() => {
      onCycleComplete?.();
      setCycle((current) => current + 1);
    }, WINS_HOLD_MS);
    return () => {
      window.clearInterval(id);
    };
  }, [loop, reduceMotion, onCycleComplete]);

  return (
    // The recap's arrangement — `PostClassScaffold`, resolved from the tenant's
    // `celebration_format` (./celebrations/CelebrationFrame.tsx). The shipped
    // value re-applies this screen's own `Padding(vertical: spacingBig) > Center`.
    <CelebrationFrame>
      <WinsContent key={cycle} />
    </CelebrationFrame>
  );
}

/** `_WinsContent` — `Column(min, stretch, spacing: spacingBig)`. */
function WinsContent() {
  const stats = SHOWCASE_WINS_STATS;
  const title = useThemeText(SLOT_WINS_TITLE, stats.title);
  const subtitle = useThemeText(SLOT_WINS_SUBTITLE, stats.subtitle);

  return (
    <div className={styles.content} style={showcaseStyle(MOTION_VARS)}>
      {/* `SizedBox(hero) > Stack(alignment: center)` — Flutter's stack clips. */}
      <div className={styles.hero}>
        {/* `Positioned.fill(child: SparkleBurst(...))`. */}
        <SparkleBurst className={styles.sparkle} />
        {/* `StaggeredReveal(offset: 0)` — a pure fade, no slide. */}
        <div className={styles.trophy}>
          <ThemedImage
            className={styles.trophyImg}
            slot={SLOT_TROPHY_IMAGE}
            fallbackSrc={showcaseAsset(stats.heroAsset)}
            alt=""
          />
        </div>
      </div>

      {/* `Column(min, spacing: spacingMedium)`. */}
      <div className={styles.headings}>
        <p className={styles.title}>{title}</p>
        <p className={styles.subtitle}>{subtitle}</p>
      </div>

      <WinsTileRow tiles={stats.tiles} baseDelayMs={TILE_BASE_DELAY_MS} />
    </div>
  );
}
