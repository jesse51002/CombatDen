// Ports ../../../../../../../MobileApp/lib/features/profile/presentation/
// layouts/rank_stat_tiles.dart.
//
// `RankFormat.statTiles` — A DASHBOARD.
//
// A board opens the screen (current rank, the range selector, the next rank)
// and the plot runs full bleed beneath it. The most data-forward of the five.
//
// THE STREAK HERO SITS ABOVE THE BOARD, UNWRAPPED. It is the app's celebration
// signature and renders at its own intrinsic size; a tile imposes a fixed
// height, which is what forced an earlier scale-down that read as squashed
// rather than small. The board stays a board beneath it.

import { NextRankSection } from '../NextRankSection';
import { RankHeader } from '../RankHeader';
import { RankTile } from '../RankTile';
import { RatingGraph } from '../RatingGraph';
import { TimeframeSelector } from '../TimeframeSelector';
import type { RankLayoutData } from '../rankLayoutData';
import { RankStreakHero, RankTopbar } from '../rankLayoutData';

import { LevelUpVideos } from './LevelUpVideos';
import styles from './rankLayouts.module.css';

export function RankStatTiles({ data }: { data: RankLayoutData }) {
  return (
    // `Column(mainAxisSize: min, stretch, spacing: spacingBig)`.
    <div className={styles.page}>
      <RankTopbar data={data} />

      {/*
        `Padding(horizontal: screenHorizontalPadding) > Column(stretch,
        spacing: spacingMedium)`.
      */}
      <div className={`${styles.gutterScreen} ${styles.stackMedium}`}>
        <RankStreakHero weeks={data.streakWeeks} />

        {/* `_TileRow` — two equal cells. */}
        <div className={styles.tileRow}>
          <RankTile>
            <RankHeader
              rankTitle={data.rank.name}
              rankSubtitle={data.rank.subLabel}
              layout="tile"
            />
          </RankTile>
          <RankTile>
            <TimeframeSelector layout="tile" />
          </RankTile>
        </div>

        <RankTile>
          <NextRankSection rank={data.rank} layout="tile" />
        </RankTile>
      </div>

      {/* The plot as the screen's main event: tall, and run to both edges. */}
      <RatingGraph points={data.points} size="lg" bleed />

      <LevelUpVideos videos={data.levelUpVideos} />
    </div>
  );
}
