// Ports ../../../../../../../MobileApp/lib/features/rewards/presentation/
// layouts/rewards_list_rows.dart — `RewardsFormat.listRows`.
//
// The same stack as `cardGrid`, one reward per full-width row instead of two
// per grid row: square thumb leads, the price tag moves inline beside the cost,
// the action goes trailing. Titles get the full width, so the two-line clamp
// stops deciding what a reward is called.

import { PointsHeadline } from '../PointsHeadline';
import { RewardCard } from '../RewardCard';
import type { RewardsLayoutData } from '../rewardsLayoutData';
import { RewardsTabs } from '../RewardsTabs';
import { RewardsTopbar } from '../RewardsTopbar';

import styles from './RewardsListRows.module.css';
import stack from './rewardsStack.module.css';

export interface RewardsListRowsProps {
  data: RewardsLayoutData;
}

export function RewardsListRows({ data }: RewardsListRowsProps) {
  return (
    <div className={stack.scrollStack} data-rewards-format="listRows">
      <RewardsTopbar data={data} />
      <RewardsTabs active="pointsStore" />
      <PointsHeadline points={data.totalPoints} />
      {/* `_RowList` — `Padding(horizontal: screenHorizontalPadding) > Column`. */}
      <div className={styles.rows}>
        {data.items.map((item, index) => (
          // The slot index IS the card's identity — two rewards may
          // legitimately share a title (../StoreGrid.tsx makes the same call).
          <RewardCard
            key={`${String(index)}-${item.title}`}
            item={item}
            buttonText="Redeem"
            layout="thumbLeft"
          />
        ))}
      </div>
    </div>
  );
}
