// Ports ../../../../../../../MobileApp/lib/features/rewards/presentation/
// layouts/rewards_card_grid.dart — `RewardsFormat.cardGrid`, the points store
// that ships today.
//
// One scroll: topbar, tab strip, points headline, then a two-up grid of
// image-top cards. It reproduces the previous body value for value, so a tenant
// with no `rewards_format` slot sees no change — which is why
// ../__tests__/rewardsFormats.test.tsx freezes ../StoreGrid.tsx's markup rather
// than merely counting its parts.

import { PointsHeadline } from '../PointsHeadline';
import type { RewardsLayoutData } from '../rewardsLayoutData';
import { RewardsTabs } from '../RewardsTabs';
import { RewardsTopbar } from '../RewardsTopbar';
import { StoreGrid } from '../StoreGrid';

import styles from './rewardsStack.module.css';

export interface RewardsCardGridProps {
  data: RewardsLayoutData;
}

export function RewardsCardGrid({ data }: RewardsCardGridProps) {
  return (
    <div className={styles.scrollStack} data-rewards-format="cardGrid">
      <RewardsTopbar data={data} />
      <RewardsTabs active="pointsStore" />
      <PointsHeadline points={data.totalPoints} />
      <StoreGrid items={data.items} />
    </div>
  );
}
