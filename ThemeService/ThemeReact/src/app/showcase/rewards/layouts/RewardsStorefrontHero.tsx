// Ports ../../../../../../../MobileApp/lib/features/rewards/presentation/
// layouts/rewards_storefront_hero.dart — `RewardsFormat.storefrontHero`, the
// retail storefront.
//
// The first reward is promoted to a full-bleed hero with its title, cost and
// action riding the image; the points headline drops BELOW it, and the
// remaining rewards fall into the same two-up grid `cardGrid` uses.
//
// THE PROMOTED REWARD IS NOT A COPY — it is taken OUT of the grid (`skip(1)`),
// so every reward still appears exactly once. A one-reward store therefore
// renders one hero and an empty grid, never the same reward twice; that case is
// its own assertion in ../__tests__/rewardsFormats.test.tsx.

import { PointsHeadline } from '../PointsHeadline';
import { RewardCard } from '../RewardCard';
import type { RewardsLayoutData } from '../rewardsLayoutData';
import { RewardsTabs } from '../RewardsTabs';
import { RewardsTopbar } from '../RewardsTopbar';
import { StoreGrid } from '../StoreGrid';

import styles from './rewardsStack.module.css';

export interface RewardsStorefrontHeroProps {
  data: RewardsLayoutData;
}

export function RewardsStorefrontHero({ data }: RewardsStorefrontHeroProps) {
  // Dart reads `rewards.first`, which its `hasStatus` branch has already
  // guaranteed is there. This browser has no load state (../rewardsLayoutData.ts),
  // so the guard is the destructure itself — an empty store simply shows no
  // hero rather than throwing.
  const [promoted, ...rest] = data.items;
  return (
    <div className={styles.scrollStack} data-rewards-format="storefrontHero">
      <RewardsTopbar data={data} />
      <RewardsTabs active="pointsStore" layout="segmented" />
      {promoted !== undefined && (
        <RewardCard item={promoted} buttonText="Redeem" layout="hero" />
      )}
      <PointsHeadline points={data.totalPoints} />
      <StoreGrid items={rest} />
    </div>
  );
}
