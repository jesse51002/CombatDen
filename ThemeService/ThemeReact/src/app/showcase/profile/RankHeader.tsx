// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// rank_summary/rank_header.dart — the member's belt art beside their rank name,
// with the sub-rank label under it.
//
// THE BELT IS A THEME SLOT HERE, WHICH IS THE POINT. Dart's ladder is the
// member's own `rank.image_url` (the gym's real belt art) over a bundled
// fallback; there is no member in this browser, so the ladder starts one rung
// lower and the ACTIVE THEME's `rank_belt` is what renders — the same rung
// ../support/ShowcaseTopbar.tsx's info bar already uses for this slot. Switching
// theme therefore re-belts the member, which is exactly the claim the preview
// exists to make.

import { ThemedImage } from 'theme-react';

import { showcaseAsset } from '../showcaseAssets';
import { SLOT_RANK_BELT } from '../showcaseSlots';

import styles from './RankHeader.module.css';

export interface RankHeaderProps {
  rankTitle: string;
  rankSubtitle?: string | undefined;
}

export function RankHeader({ rankTitle, rankSubtitle }: RankHeaderProps) {
  return (
    // `Row(mainAxisAlignment: center, mainAxisSize: min, spacing: spacingLarge)`.
    <div className={styles.header}>
      {/* `_Belt` — 77x50, `BoxFit.contain`. A per-asset dimension, not a token. */}
      <ThemedImage
        className={styles.belt}
        slot={SLOT_RANK_BELT}
        fallbackSrc={showcaseAsset('profile_rank_belt_gold.png')}
        alt=""
      />
      {/* `Column(min, center, spacing: spacingSmall)`. */}
      <div className={styles.names}>
        <span className={styles.title}>{rankTitle}</span>
        {rankSubtitle !== undefined && rankSubtitle !== '' && (
          <span className={styles.subtitle}>{rankSubtitle}</span>
        )}
      </div>
    </div>
  );
}
