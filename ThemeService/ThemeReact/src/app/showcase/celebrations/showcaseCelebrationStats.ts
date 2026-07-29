// Ports ../../../../../../CRM/lib/showcase/celebrations/showcase_celebration_stats.dart.
//
// The hardcoded post-class celebration data for the showcase island — clones of
// MobileApp's `mock_stats.dart` mock models + const values, kept verbatim so the
// showcase reads identically to the member app. Visual prototype only: none of
// it is a customization slot, and none of it is a member's real numbers.
//
// The `imageAsset` fields name a bundled PNG by the same filename ../showcaseAssets.ts
// keys its map with, so a reward item resolves one-to-one with the Dart.

import type { ShowcaseAssetFile } from '../showcaseAssets';

/** `ShowcaseWinTile`. */
export interface ShowcaseWinTile {
  /**
   * One of `'star'` / `'award'` / `'gift'`. Mapped to a glyph in the widget and
   * stored as a string so it survives a future JSON round-trip.
   */
  readonly iconName: string;
  readonly value: string;
  readonly label: string;
}

/** `ShowcaseWinsStats`. */
export interface ShowcaseWinsStats {
  readonly title: string;
  readonly subtitle: string;
  readonly heroAsset: ShowcaseAssetFile;
  readonly tiles: readonly ShowcaseWinTile[];
}

/** `ShowcasePointsStats`. */
export interface ShowcasePointsStats {
  /** Points earned from this class — rolls 0 → `gained` in the count-up. */
  readonly gained: number;
  /**
   * The member's all-time points balance, shown in the small caption pinned to
   * the bottom of the points screen.
   */
  readonly totalPoints: number;
}

/** `ShowcaseRewardItem`. */
export interface ShowcaseRewardItem {
  /**
   * Network image (the injected gym's reward photo); preferred over
   * `imageAsset` when set. Absent for the bundled sample items below.
   */
  readonly imageUrl?: string | undefined;
  readonly imageAsset: ShowcaseAssetFile;
  readonly name: string;
  readonly discountLabel: string;
  readonly pointsCost: number;
}

/** `ShowcaseRewardsStats`. */
export interface ShowcaseRewardsStats {
  readonly title: string;
  readonly subtitle: string;
  readonly featuredIndex: number;
  readonly items: readonly ShowcaseRewardItem[];
}

/** `showcaseWinsStats`. */
export const SHOWCASE_WINS_STATS: ShowcaseWinsStats = Object.freeze({
  title: 'Today’s wins',
  subtitle: 'The grind never stops',
  heroAsset: 'stat_wins_trophy.png',
  tiles: Object.freeze([
    Object.freeze({ iconName: 'star', value: '3 week', label: 'Streak' }),
    Object.freeze({ iconName: 'award', value: '28', label: 'Rank Classes' }),
    Object.freeze({ iconName: 'gift', value: '+160', label: 'Points' }),
  ]),
});

/** `showcasePointsStats`. */
export const SHOWCASE_POINTS_STATS: ShowcasePointsStats = Object.freeze({
  gained: 160,
  totalPoints: 3400,
});

/** `showcaseRewardsStats`. */
export const SHOWCASE_REWARDS_STATS: ShowcaseRewardsStats = Object.freeze({
  title: 'Rewards You Can Get',
  subtitle: 'Swipe to view rewards',
  featuredIndex: 1,
  items: Object.freeze([
    Object.freeze({
      imageAsset: 'reward_bring_friend.png',
      name: 'Bring a friend',
      discountLabel: 'Free',
      pointsCost: 800,
    }),
    Object.freeze({
      imageAsset: 'reward_mma_tshirt.png',
      name: 'Gym t-shirt',
      discountLabel: 'Free',
      pointsCost: 2200,
    }),
    Object.freeze({
      imageAsset: 'reward_private_training.png',
      name: 'Private Training',
      discountLabel: '50% off',
      pointsCost: 3500,
    }),
  ]),
});
