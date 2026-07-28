// Ports ../../../../../../../MobileApp/lib/features/profile/presentation/
// layouts/rank_belt_hero.dart.
//
// `RankFormat.beltHero` — THE BELT LEADS.
//
// The current belt becomes a full-width band with the streak statement over it,
// and the next-rank rail runs directly beneath, so "where I am" and "what is
// next" are one glance instead of two scroll positions. The plot demotes to a
// card lower down.
//
// THIS IS THE ONE ARRANGEMENT THAT DOES NOT USE `NextRankSection`: it splits
// the four next-rank elements across two regions — the progress rail under the
// band, then the badge, title and label as a row beneath it. All four still
// render exactly once, which is what the invariant gate checks.

import {
  BADGE_INLINE,
  NEXT_RANK_TITLE,
  NextRankBadge,
  NextRankProgress,
  NextRankProgressLabel,
  NextRankTitle,
  nextRankProgress,
} from '../NextRankSection';
import { RankHeader } from '../RankHeader';
import { RatingGraph } from '../RatingGraph';
import { TimeframeSelector } from '../TimeframeSelector';
import type { RankLayoutData } from '../rankLayoutData';
import { RankStreakHero, RankTopbar } from '../rankLayoutData';

import { LevelUpVideos } from './LevelUpVideos';
import styles from './rankLayouts.module.css';

export function RankBeltHero({ data }: { data: RankLayoutData }) {
  const { progress, label } = nextRankProgress(data.rank);

  return (
    // `Column(mainAxisSize: min, stretch, spacing: spacingBig)`.
    <div className={styles.page}>
      <RankTopbar data={data} />

      {/* `Column(stretch, spacing: spacingMedium)` — band, rail, next-rank row. */}
      <div className={styles.stackMedium}>
        {/*
          `Stack(alignment: topCenter)`. The hero gets its own cell wrapper
          rather than being placed directly: the part markers are
          `display: contents` (../rankLayoutData.module.css), so a marker is not
          a grid item and the stack cannot address the hero through one.
        */}
        <div className={styles.beltStack}>
          <RankHeader
            rankTitle={data.rank.name}
            rankSubtitle={data.rank.subLabel}
            layout="beltBleed"
          />
          <div className={styles.beltStackOverlay}>
            <RankStreakHero weeks={data.streakWeeks} />
          </div>
        </div>

        {/* Full bleed, square-ended: the seam between the band and the words. */}
        <NextRankProgress progress={progress} layout="rail" />

        {/* `Padding(horizontal: paddingBig) > Row(center, spacing: spacingLarge)`. */}
        <div className={`${styles.gutterBig} ${styles.beltHeroNext}`}>
          <NextRankBadge size={BADGE_INLINE} />
          <div className={styles.beltHeroNextWords}>
            <NextRankTitle title={NEXT_RANK_TITLE} />
            <NextRankProgressLabel label={label} />
          </div>
        </div>
      </div>

      <div className={styles.divider} />

      {/* `Column(stretch, spacing: spacingLarge)` — the demoted plot, on a card. */}
      <div className={styles.stackLarge}>
        <TimeframeSelector />
        <RatingGraph points={data.points} card />
      </div>

      <LevelUpVideos videos={data.levelUpVideos} />
    </div>
  );
}
