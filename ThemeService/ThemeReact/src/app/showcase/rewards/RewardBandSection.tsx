// Ports ../../../../../../MobileApp/lib/features/rewards/presentation/layouts/
// rewards_band_section.dart — one band of the price ladder: its label over a
// three-up row of tiles.
//
// The label is PRESENTATIONAL GROUPING. It carries no data the cards do not
// already carry, it never removes a reward from view, and its only variable is
// a colour (accent when the member can afford the band, `text3rd` otherwise).

import { cx } from '../cx';

import type { RewardBand } from './rewardBands';
import { RewardCard } from './RewardCard';
import styles from './RewardBandSection.module.css';

export interface RewardBandSectionProps {
  band: RewardBand;
}

export function RewardBandSection({ band }: RewardBandSectionProps) {
  return (
    // `Column(min, stretch, spacing: spacingLarge)`.
    <div className={styles.band}>
      <span className={cx(styles.label, band.affordable ? styles.affordable : styles.distant)}>
        {band.label}
      </span>
      <div className={styles.tiles}>
        {band.items.map((item, index) => (
          // The slot index IS the card's identity — two rewards may
          // legitimately share a title (../StoreGrid.tsx makes the same call).
          <RewardCard
            key={`${String(index)}-${item.title}`}
            item={item}
            buttonText="Redeem"
            layout="tile"
          />
        ))}
      </div>
    </div>
  );
}
