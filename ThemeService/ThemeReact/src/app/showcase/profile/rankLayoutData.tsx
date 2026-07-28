// Ports ../../../../../../MobileApp/lib/features/profile/presentation/layouts/
// rank_layout_data.dart, plus the two `parts/` wrappers every arrangement
// shares (`rank_topbar.dart`, `rank_streak_hero.dart`).
//
// EVERY LAYOUT RECEIVES THE SAME PAYLOAD AND MUST RENDER EVERY ELEMENT IN IT:
// the topbar, the streak hero, the current rank, the plot with its range
// selector, all four next-rank elements, and the level-up videos. A layout may
// move them and change their prominence. It may not drop one, add one, or reach
// for anything not in here — which is what keeps `rank_format` a choice of
// ARRANGEMENT.
//
// Note what is deliberately absent: any notion of rank HISTORY. The screen has
// the current rank and the next one and nothing else, so no arrangement can
// imply a progression it cannot show. (./mockRankProgress.ts's series is the
// member's class COUNT toward the rank they already hold — not a ladder of
// past ranks.)

import type { ReactNode } from 'react';

import type { ShowcaseVideo } from '../showcaseContent';
import { SparkleHero } from '../rewards/SparkleHero';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';

import { RANK_PART } from './rankParts';
import type { RankPart } from './rankParts';
import styles from './rankLayoutData.module.css';
import type { ShowcaseRank, ShowcaseRankPoint } from './mockRankProgress';

/** `_kDefaultRankBadgeAsset` — the topbar's own belt tile. */
const RANK_BADGE_ASSET = 'icon_rank_belt.png' as const;

/** Everything a rank layout may render, gathered once. */
export interface RankLayoutData {
  readonly gymName: string;
  readonly gymLogoSrc?: string | undefined;
  readonly rank: ShowcaseRank;
  readonly points: readonly ShowcaseRankPoint[];
  readonly streakWeeks: number;
  readonly pointsLabel: string;
  /** The educational head of the loaded feed; empty hides its own section. */
  readonly levelUpVideos: readonly ShowcaseVideo[];
}

/**
 * `RankTopbar` — the rank screen's topbar, built from [RankLayoutData].
 *
 * One place, so all five arrangements pass identical arguments: the SHELL's own
 * format decides how the bar is drawn, and the rank format never touches it.
 */
export function RankTopbar({ data }: { data: RankLayoutData }) {
  return (
    <RankPartMarker part={RANK_PART.topbar}>
      <ShowcaseTopbar
        mode="nameOnly"
        gymName={data.gymName}
        logoSrc={data.gymLogoSrc}
        streakDays={data.streakWeeks}
        pointsLabel={data.pointsLabel}
        rankBadgeAsset={RANK_BADGE_ASSET}
      />
    </RankPartMarker>
  );
}

/**
 * Stamps a `data-rank-part` on a component this directory does not own, so the
 * invariant gate can count it (see ./rankParts.ts for why the DOM needs one).
 *
 * `display: contents` is what makes that free: the element stays in the DOM and
 * in every query, and generates no box at all — so a marker can never move a
 * pixel of the arrangement it exists to check.
 */
function RankPartMarker({ part, children }: { part: RankPart; children: ReactNode }) {
  return (
    <div className={styles.marker} data-rank-part={part}>
      {children}
    </div>
  );
}

export { RankPartMarker };

/**
 * `RankStreakHero` — the streak statement, and the app's rationed celebration
 * signature.
 *
 * Every arrangement shows exactly ONE of these: the hero earns its weight by
 * being rare, so a layout may move it, but never multiply it and never resize
 * it. It is deliberately NOT scalable — an earlier Dart version `FittedBox`-
 * scaled the whole block to fit a cell, which shrank the type and the sparkles
 * by the same factor and read as a squashed copy rather than a smaller one. An
 * arrangement that cannot afford the hero at its own size has to give it room.
 *
 * The hero itself is ../rewards/SparkleHero.tsx, not a second copy — Dart
 * reaches the same widget by the same route.
 */
export function RankStreakHero({ weeks }: { weeks: number }) {
  return (
    <RankPartMarker part={RANK_PART.streakHero}>
      <SparkleHero top="YOU HAVE A" accent={`${String(weeks)} WEEK`} bottom="STREAK" />
    </RankPartMarker>
  );
}
