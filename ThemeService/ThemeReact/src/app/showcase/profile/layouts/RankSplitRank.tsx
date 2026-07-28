// Ports ../../../../../../../MobileApp/lib/features/profile/presentation/
// layouts/rank_split_rank.dart.
//
// `RankFormat.splitRank` — NOW OVER NEXT.
//
// The screen splits into where the member IS and what comes NEXT, with the plot
// as a strip on the seam between them. The clearest information architecture of
// the five and the least visually eventful; the streak reads as a line in the
// "now" half rather than as the hero.

import { NextRankSection } from '../NextRankSection';
import { RankGraphStrip } from '../RankGraphStrip';
import { RankHeader } from '../RankHeader';
import type { RankLayoutData } from '../rankLayoutData';
import { RankStreakHero, RankTopbar } from '../rankLayoutData';

import { LevelUpVideos } from './LevelUpVideos';
import styles from './rankLayouts.module.css';

export function RankSplitRank({ data }: { data: RankLayoutData }) {
  return (
    // `Column(mainAxisSize: min, stretch, spacing: spacingBig)`.
    <div className={styles.page}>
      <RankTopbar data={data} />

      {/* The "now" half — `Column(stretch, spacing: spacingLarge)`. */}
      <div className={styles.stackLarge}>
        <div className={styles.gutterBig}>
          <RankHeader
            rankTitle={data.rank.name}
            rankSubtitle={data.rank.subLabel}
            layout="beltLeft"
          />
        </div>
        <RankStreakHero weeks={data.streakWeeks} />
      </div>

      {/* The seam. */}
      <RankGraphStrip points={data.points} />

      {/* The "next" half — `Padding(horizontal: paddingBig)`. */}
      <div className={styles.gutterBig}>
        <NextRankSection rank={data.rank} layout="stacked" />
      </div>

      <LevelUpVideos videos={data.levelUpVideos} />
    </div>
  );
}
