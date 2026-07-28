// The member app's POINTS STORE (`PointsStoreScreen`) — the Points Store / My
// Rewards tabs, the sparkle "YOU EARNED — POINTS" hero over the member's
// balance, and the store of redeemable items.
//
// Ports ../../../../../MobileApp/lib/features/rewards/presentation/layouts/
// rewards_layout.dart: this file is the FRAME plus the `rewards_format` switch,
// exactly as `RewardsLayout` is. It was a port of `CRM/lib/showcase/
// rewards_showcase.dart` when the store had one arrangement; the CRM clone has
// no format seam, so the member app is now the port of record and the five
// bodies live in ./rewards/layouts/.
//
// NOT to be confused with ./RewardsCardShowcase.tsx, which ports
// `rewards_card_showcase.dart` — the animated post-class rewards CELEBRATION.
// The two Dart files are named that way and the ports keep their names, because
// a reviewer runs the two side by side. This screen is registered as `store`;
// that one is registered as `rewards`.
//
// THE FRAME IS PART OF THE ARRANGEMENT, which is why the switch lives here and
// not one level down. Dart's own note: the formats differ in whether the
// headline scrolls away or pins, and that is a question about the frame rather
// than about its contents. Three arrangements scroll as one surface and pass
// `bodyScroll`; two pin their chrome and scroll only the store, so they must
// NOT — their inner `Expanded` scroller needs a body with a definite height,
// and a second scroller around it would fight it.
//
// A STATIC SURFACE. `loop` / `onCycleComplete` exist on the Dart showcase
// widget only to keep the seven screens' API uniform and are unused there; the
// port does not take them. The one thing that animates is the hero's sparkle
// scatter, which fires once on mount (./rewards/SparkleHero.tsx).
//
// WHAT IS THE GYM'S AND WHAT IS THE MEMBER'S: see ./rewards/rewardsLayoutData.ts.
//
// THE HERO ESCAPES ITS BOX AND SURVIVES ANYWAY. The body clips horizontally in
// both modes (see ./support/ShowcaseScaffold.tsx), which would have been fatal
// for the scatter — it is `Clip.none` and reaches 172px either side of centre.
// It survives because the hero is full-bleed: at the phone's 390 logical px the
// farthest sparkle lands at x = 23 and x = 367, inside the body on both sides.

import type { ReactElement } from 'react';

import { FORMAT_SLOTS, REWARDS_FORMATS, useFormat } from './formats';
import { RewardsCardGrid } from './rewards/layouts/RewardsCardGrid';
import { RewardsListRows } from './rewards/layouts/RewardsListRows';
import { RewardsPosterDeck } from './rewards/layouts/RewardsPosterDeck';
import { RewardsPriceLadder } from './rewards/layouts/RewardsPriceLadder';
import { RewardsStorefrontHero } from './rewards/layouts/RewardsStorefrontHero';
import type { ShowcasePointsStoreItem } from './rewards/mockPointsStore';
import { SHOWCASE_POINTS_STORE_DATA } from './rewards/mockPointsStore';
import type { RewardsLayoutData } from './rewards/rewardsLayoutData';
import type { ShowcaseReward } from './showcaseContent';
import { ShowcaseBottomNav } from './support/ShowcaseBottomNav';
import { ShowcaseScaffold } from './support/ShowcaseScaffold';

/** `RewardsShowcase.gymName`'s default. */
const DEFAULT_GYM_NAME = 'Your Gym';

/**
 * The injected gym rewards as store cards, or the bundled sample items. Ports
 * the `rewards != null && rewards.isNotEmpty` branch in `build`.
 *
 * The card's own `imageAsset` stays absent for an injected reward, exactly as
 * Dart leaves it null: the gym's photo URL is what renders, and a dead one
 * degrades to the flat `card` rectangle (./rewards/rewardCardParts.tsx).
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
  const format = useFormat(FORMAT_SLOTS.rewards, REWARDS_FORMATS, 'cardGrid');
  const sample = SHOWCASE_POINTS_STORE_DATA;

  // One payload, handed unchanged to whichever arrangement renders. There is
  // deliberately no second source for a variant to reach into.
  const data: RewardsLayoutData = {
    gymName,
    gymLogoSrc,
    streakDays: sample.streakDays,
    pointsLabel: sample.pointsLabel,
    rankBadgeAsset: sample.rankBadgeAsset,
    totalPoints: sample.totalPoints,
    items: storeItemsFor(rewards),
  };

  // Exhaustive over `RewardsFormat` — a new arrangement fails to typecheck here
  // until it is built.
  let body: ReactElement;
  switch (format) {
    case 'cardGrid':
      body = <RewardsCardGrid data={data} />;
      break;
    case 'listRows':
      body = <RewardsListRows data={data} />;
      break;
    case 'posterDeck':
      body = <RewardsPosterDeck data={data} />;
      break;
    case 'priceLadder':
      body = <RewardsPriceLadder data={data} />;
      break;
    case 'storefrontHero':
      body = <RewardsStorefrontHero data={data} />;
      break;
  }

  // See the header: the two pinned arrangements own their own scroller.
  const bodyScroll = format !== 'posterDeck' && format !== 'priceLadder';

  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll={bodyScroll}
      bottomNav={<ShowcaseBottomNav selected="reward" />}
    >
      {body}
    </ShowcaseScaffold>
  );
}
