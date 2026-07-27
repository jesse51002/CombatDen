// Ports ../../../../../CRM/lib/showcase/rewards_showcase.dart — an exact visual
// clone of the member app's POINTS STORE (`PointsStoreScreen`): the Points
// Store / My Rewards tabs, the sparkle "YOU EARNED — POINTS" hero over the
// member's balance, and the two-column store of redeemable items.
//
// NOT to be confused with ./RewardsCardShowcase.tsx, which ports
// `rewards_card_showcase.dart` — the animated post-class rewards CELEBRATION.
// The two Dart files are named that way and the ports keep their names, because
// a reviewer runs the two side by side.
//
// A STATIC surface. `loop` / `onCycleComplete` exist on the Dart widget only to
// keep the seven screens' API uniform and are unused there; the port simply
// does not take them, because nothing in this browser passes them and an
// ignored prop is a lie about what the screen does. The one thing that does
// animate is the hero's sparkle scatter, which fires once on mount
// (./rewards/SparkleHero.tsx).
//
// WHAT IS THE GYM'S AND WHAT IS THE MEMBER'S. `gymName` / `gymLogoSrc` are the
// HOST's gym identity and are NOT customization slots — a theme pick must never
// rename the mock's gym. `rewards` is the gym's real catalogue. Everything else
// on this screen — the streak, the points balance, the rank badge — is
// PER-MEMBER chrome and stays sample data even when a gym's rewards are
// injected (rewards_showcase.dart:18-20).
//
// IT DELIBERATELY OVERFLOWS. Dart wraps the column in
// `ClipRect > OverflowBox(maxHeight: infinity, alignment: topCenter)`: the
// store lays out at its natural height, top-aligned, and whatever falls past
// the phone's edge is clipped rather than scrolled or reported as an overflow
// error. Here the scaffold body already clips, so the column just grows.

import { PointsHeadline } from './rewards/PointsHeadline';
import { RewardsTabs } from './rewards/RewardsTabs';
import type { ShowcasePointsStoreItem } from './rewards/mockPointsStore';
import { SHOWCASE_POINTS_STORE_DATA } from './rewards/mockPointsStore';
import { StoreGrid } from './rewards/StoreGrid';
import styles from './RewardsShowcase.module.css';
import type { ShowcaseReward } from './showcaseContent';
import { ShowcaseBottomNav } from './support/ShowcaseBottomNav';
import { ShowcaseScaffold } from './support/ShowcaseScaffold';
import { ShowcaseTopbar } from './support/ShowcaseTopbar';

/** `RewardsShowcase.gymName`'s default. */
const DEFAULT_GYM_NAME = 'Your Gym';

/**
 * The injected gym rewards as store cards, or the bundled sample items. Ports
 * the `rewards != null && rewards.isNotEmpty` branch in `build`.
 *
 * The card's own `imageAsset` stays absent for an injected reward, exactly as
 * Dart leaves it null: the gym's photo URL is what renders, and a dead one
 * degrades to the flat `card` rectangle (./rewards/RewardCard.tsx).
 */
export function storeItemsFor(
  rewards: readonly ShowcaseReward[] | null | undefined,
): readonly ShowcasePointsStoreItem[] {
  if (rewards === null || rewards === undefined || rewards.length === 0) {
    return SHOWCASE_POINTS_STORE_DATA.items;
  }
  return rewards.map((reward) => ({
    title: reward.title,
    priceLabel: reward.priceLabel,
    pointsCost: reward.pointsCost,
    imageUrl: reward.imageUrl,
  }));
}

export interface RewardsShowcaseProps {
  /** The host gym's name. There is no gym in this browser. */
  gymName?: string;
  /** The host gym's real logo URL. Absent here. */
  gymLogoSrc?: string | undefined;
  /** The gym's real rewards; null falls back to the bundled sample items. */
  rewards?: readonly ShowcaseReward[] | null;
}

export function RewardsShowcase({
  gymName = DEFAULT_GYM_NAME,
  gymLogoSrc,
  rewards,
}: RewardsShowcaseProps) {
  const data = SHOWCASE_POINTS_STORE_DATA;
  const items = storeItemsFor(rewards);

  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bottomNav={<ShowcaseBottomNav selected="reward" />}
    >
      {/* `Column(mainAxisSize: min, stretch, spacing: spacingBig)`. */}
      <div className={styles.store}>
        <ShowcaseTopbar
          mode="nameOnly"
          gymName={gymName}
          logoSrc={gymLogoSrc}
          streakDays={data.streakDays}
          pointsLabel={data.pointsLabel}
          rankBadgeAsset={data.rankBadgeAsset}
        />
        <RewardsTabs active="pointsStore" />
        <PointsHeadline points={data.totalPoints} />
        <StoreGrid items={items} />
      </div>
    </ShowcaseScaffold>
  );
}
