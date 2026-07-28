// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// next_rank/{next_rank_section,next_rank_badge}.dart — "Next Rank / X / Y
// classes" beside a circular belt badge whose progress ring tracks how close
// the member is.
//
// THIS IS THE SLOT'S ONLY CONSUMER, AND THE REASON THIS SCREEN EXISTS. The
// pipeline derives `next_rank_belt_image` from `rank_belt`
// (`ThemeService/apps/combatden/app.yaml`, `depends_on: rank_belt`) and has
// produced it for all 76 themes; `next_rank_badge.dart:89` is the one widget in
// the member app that reads it, and the preview never carried Profile — so a
// tenth generated image per theme has been shipping to nothing. Rendering it
// here is what closes that loop.
//
// The Dart ladder is the payload's `next_rank_image_url` (the gym's real belt
// art) OVER the themed slot OVER the bundled asset. There is no member in this
// browser, so the ladder starts at the themed slot, exactly as ./RankHeader.tsx
// does for the current belt — which is what makes the two belts differ per
// theme rather than being one asset drawn twice.
//
// The ring is an SVG arc rather than a `CustomPaint`: one static stroke between
// two fixed endpoints has no per-frame value for a canvas to buy.

import { ThemedImage } from 'theme-react';

import { showcaseAsset } from '../showcaseAssets';
import { SLOT_NEXT_RANK_BELT_IMAGE } from '../showcaseSlots';
import { SC } from '../showcaseTokens';

import styles from './NextRankSection.module.css';
import type { ShowcaseRank } from './mockRankProgress';

/** `_kBadgeSize`. A per-asset layout dimension, not a design token. */
const BADGE_SIZE = 100;

/** The arc's radius in the viewBox, inset by half the stroke as Dart deflates. */
const ARC_RADIUS = (BADGE_SIZE - SC.buttonBorderSize) / 2;
const ARC_CIRCUMFERENCE = 2 * Math.PI * ARC_RADIUS;

/**
 * `NextRankSection.build`'s arithmetic, verbatim: at the top of the ladder
 * there is no target, so the ring reads empty and the label names the state
 * instead of printing "17 / 0 classes".
 */
export function nextRankProgress(rank: ShowcaseRank): { progress: number; label: string } {
  const target = rank.classesTillNextStep;
  const done = rank.classesSinceRank;
  if (target <= 0) return { progress: 0, label: 'Top of the ladder.' };
  const raw = done / target;
  return {
    progress: raw < 0 ? 0 : raw > 1 ? 1 : raw,
    label: `${String(done)} / ${String(target)} classes`,
  };
}

export interface NextRankSectionProps {
  rank: ShowcaseRank;
}

export function NextRankSection({ rank }: NextRankSectionProps) {
  const { progress, label } = nextRankProgress(rank);

  return (
    // `Padding(horizontal: paddingBig) > Row(center, spacing: spacingMedium)`.
    <div className={styles.section}>
      {/* `Expanded > Column(min, start, spacing: spacingSmall)`. */}
      <div className={styles.text}>
        <span className={styles.heading}>Next Rank</span>
        <span className={styles.progressLabel}>{label}</span>
      </div>
      <NextRankBadge progress={progress} />
    </div>
  );
}

/** `NextRankBadge` — `SizedBox(100) > Stack(belt, progress arc)`. */
function NextRankBadge({ progress }: { progress: number }) {
  return (
    <div className={styles.badge}>
      {/* `Padding(all: _kImageInset) > Center > _ThemedBelt`. */}
      <div className={styles.beltInset}>
        <ThemedImage
          className={styles.belt}
          slot={SLOT_NEXT_RANK_BELT_IMAGE}
          fallbackSrc={showcaseAsset('profile_next_rank_belt.png')}
          alt=""
        />
      </div>
      {/*
        `_ProgressArcPainter` — `drawArc(rect.deflate(strokeWidth / 2),
        -pi/2, progress * 2pi, strokeCap: round)`.

        The -90 degree rotation is the `-1.5708` start angle; the dash pair is
        the sweep. `pathLength` is deliberately NOT used: a round cap on a
        zero-length dash still paints a dot, and at the top of the ladder
        (progress 0) the badge must show an empty ring, so the dash length is
        left at a true zero.
      */}
      <svg
        className={styles.arc}
        viewBox={`0 0 ${String(BADGE_SIZE)} ${String(BADGE_SIZE)}`}
        fill="none"
        aria-hidden="true"
        focusable="false"
      >
        <circle
          cx={BADGE_SIZE / 2}
          cy={BADGE_SIZE / 2}
          r={ARC_RADIUS}
          stroke="currentColor"
          strokeWidth={SC.buttonBorderSize}
          strokeLinecap="round"
          strokeDasharray={`${String(ARC_CIRCUMFERENCE * progress)} ${String(ARC_CIRCUMFERENCE)}`}
          transform={`rotate(-90 ${String(BADGE_SIZE / 2)} ${String(BADGE_SIZE / 2)})`}
        />
      </svg>
    </div>
  );
}
