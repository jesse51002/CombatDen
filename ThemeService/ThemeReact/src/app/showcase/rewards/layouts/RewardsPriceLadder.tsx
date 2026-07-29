// Ports ../../../../../../../MobileApp/lib/features/rewards/presentation/
// layouts/rewards_price_ladder.dart — `RewardsFormat.priceLadder`, the store as
// a savings ladder.
//
// The points headline PINS above the content so the member's balance stays on
// screen while they scroll, and the rewards group into cost bands, cheapest
// first, each labelled by how far off it is.
//
// THE BALANCE IS THE AFFORDABILITY BAR, and there is no second one. The bands
// come from `pointsCost` and `totalPoints` — both already on the shipped screen
// — so nothing new is fetched and, just as importantly, nothing new is PRINTED:
// the three band labels are fixed words, not a computed gap, a percentage or a
// progress figure. What makes the ladder legible as affordability is that the
// pinned headline never leaves while the ladder moves under it. See
// ../rewardBands.ts, and ../__tests__/rewardsFormats.test.tsx, which asserts the
// digits on screen are identical across all five arrangements.

import { PointsHeadline } from '../PointsHeadline';
import { RewardBandSection } from '../RewardBandSection';
import { rewardBands } from '../rewardBands';
import type { RewardsLayoutData } from '../rewardsLayoutData';
import { RewardsTabs } from '../RewardsTabs';
import { RewardsTopbar } from '../RewardsTopbar';

import styles from './RewardsPriceLadder.module.css';
import stack from './rewardsStack.module.css';

export interface RewardsPriceLadderProps {
  data: RewardsLayoutData;
}

export function RewardsPriceLadder({ data }: RewardsPriceLadderProps) {
  const bands = rewardBands(data.items, data.totalPoints);
  return (
    <div className={stack.pinnedStack} data-rewards-format="priceLadder">
      <RewardsTopbar data={data} />
      <RewardsTabs active="pointsStore" />
      <PointsHeadline points={data.totalPoints} />
      {/* `Expanded(child: _Bands)` — the only thing that scrolls. */}
      <div className={styles.bands}>
        {bands.map((band) => (
          <RewardBandSection key={band.label} band={band} />
        ))}
      </div>
    </div>
  );
}
