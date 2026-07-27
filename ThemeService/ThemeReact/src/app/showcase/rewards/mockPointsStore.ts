// Ports ../../../../../../CRM/lib/showcase/rewards/mock_points_store.dart — a
// clone of MobileApp's `mock_points_store.dart` with the brand name
// generalised.
//
// Dummy data for the Points Store preview. None of it is a customization slot
// and none of it is a member's real numbers: the streak, the points balance and
// the rank badge are PER-MEMBER chrome, which is why the store keeps them
// sample even when the host injects a gym's real rewards (rewards_showcase.dart:18-20).

import type { ShowcaseAssetFile } from '../showcaseAssets';

/** `ShowcasePointsStoreItem` — one redeemable card in the grid. */
export interface ShowcasePointsStoreItem {
  readonly title: string;
  /** Paid on top of the points: "Free", "30% off". */
  readonly priceLabel: string;
  readonly pointsCost: number;
  /** Bundled fallback image — what the const sample data below uses. */
  readonly imageAsset?: ShowcaseAssetFile | undefined;
  /** Injected gym reward photo (a network URL); wins over `imageAsset`. */
  readonly imageUrl?: string | undefined;
}

/** `ShowcasePointsStoreData`. */
export interface ShowcasePointsStoreData {
  readonly gymName: string;
  readonly gymLogoAsset: ShowcaseAssetFile;
  readonly streakDays: number;
  readonly pointsLabel: string;
  /**
   * The topbar's belt art. Typed as the one filename rather than any bundled
   * asset, because ../support/ShowcaseTopbar.tsx's own prop is that literal.
   */
  readonly rankBadgeAsset: 'icon_rank_belt.png';
  readonly totalPoints: number;
  readonly items: readonly ShowcasePointsStoreItem[];
}

/** `showcasePointsStoreData`, verbatim. */
export const SHOWCASE_POINTS_STORE_DATA: ShowcasePointsStoreData = Object.freeze({
  gymName: 'Your Gym',
  gymLogoAsset: 'gym_logo_global_mma.png',
  streakDays: 3,
  pointsLabel: '3.4k',
  rankBadgeAsset: 'icon_rank_belt.png',
  totalPoints: 3400,
  items: Object.freeze([
    Object.freeze({
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 800,
      imageAsset: 'reward_bring_friend.png',
    }),
    Object.freeze({
      title: 'Hand wraps',
      priceLabel: '30% off',
      pointsCost: 1500,
      imageAsset: 'reward_hand_wraps.png',
    }),
    // The newline is the Dart's own and is load-bearing: the card reserves two
    // lines of title, and this is the item that uses both.
    Object.freeze({
      title: 'Private Training\n(15 min)',
      priceLabel: 'Free',
      pointsCost: 1800,
      imageAsset: 'reward_private_training_short.png',
    }),
    Object.freeze({
      title: 'Gym t-shirt',
      priceLabel: 'Free',
      pointsCost: 2200,
      imageAsset: 'reward_mma_tshirt.png',
    }),
    Object.freeze({
      title: 'Boxing gloves',
      priceLabel: '10% off',
      pointsCost: 2500,
      imageAsset: 'reward_gloves.png',
    }),
    Object.freeze({
      title: 'Private Training',
      priceLabel: '50% off',
      pointsCost: 3500,
      imageAsset: 'reward_private_training.png',
    }),
  ]),
});
