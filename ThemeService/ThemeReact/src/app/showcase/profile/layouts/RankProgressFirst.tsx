// Ports ../../../../../../../MobileApp/lib/features/profile/presentation/
// layouts/rank_progress_first.dart.
//
// `RankFormat.progressFirst` — THE ARC LEADS.
//
// Next-rank progress is promoted to a large arc with the belt inside it,
// answering the one question a graded-art member opens this screen to ask. The
// streak drops to a line under it and the current rank to a row beneath that;
// the plot keeps the foot of the screen behind a segmented range track.

import { NextRankSection } from '../NextRankSection';
import { RankHeader } from '../RankHeader';
import { RatingGraph } from '../RatingGraph';
import { TimeframeSelector } from '../TimeframeSelector';
import type { RankLayoutData } from '../rankLayoutData';
import { RankStreakHero, RankTopbar } from '../rankLayoutData';

import { LevelUpVideos } from './LevelUpVideos';
import styles from './rankLayouts.module.css';

export function RankProgressFirst({ data }: { data: RankLayoutData }) {
  return (
    // `Column(mainAxisSize: min, stretch, spacing: spacingBig)`.
    <div className={styles.page}>
      <RankTopbar data={data} />

      {/* `Padding(horizontal: paddingBig) > NextRankSection(arc)`. */}
      <div className={styles.gutterBig}>
        <NextRankSection rank={data.rank} layout="arc" />
      </div>

      {/* `Column(stretch, spacing: spacingLarge)` — the demoted "now" half. */}
      <div className={styles.stackLarge}>
        <RankStreakHero weeks={data.streakWeeks} />
        <div className={styles.gutterBig}>
          <RankHeader
            rankTitle={data.rank.name}
            rankSubtitle={data.rank.subLabel}
            layout="beltLeft"
          />
        </div>
      </div>

      <div className={styles.divider} />

      {/* `Column(stretch, spacing: spacingLarge)` — the range track over the plot. */}
      <div className={styles.stackLarge}>
        <div className={styles.gutterBig}>
          <TimeframeSelector layout="segmented" />
        </div>
        <RatingGraph points={data.points} />
      </div>

      <LevelUpVideos videos={data.levelUpVideos} />
    </div>
  );
}
