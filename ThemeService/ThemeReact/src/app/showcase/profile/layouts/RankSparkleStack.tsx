// Ports ../../../../../../../MobileApp/lib/features/profile/presentation/
// layouts/rank_sparkle_stack.dart.
//
// `RankFormat.sparkleStack` — THE ARRANGEMENT THAT SHIPS TODAY.
//
// Streak hero at full size, then the rank summary (current rank, plot, range
// pills), the next rank, and the level-up videos, each separated by a rule.
// This reproduces the previous ProfileShowcase rendering value for value, so a
// tenant with no layout slot sees no change — and ../__tests__/
// rankFormats.test.tsx asserts exactly that against the recorded baseline.

import { NextRankSection } from '../NextRankSection';
import { RankSummarySection } from '../RankSummarySection';
import type { RankLayoutData } from '../rankLayoutData';
import { RankStreakHero, RankTopbar } from '../rankLayoutData';

import { LevelUpVideos } from './LevelUpVideos';
import styles from './rankLayouts.module.css';

export function RankSparkleStack({ data }: { data: RankLayoutData }) {
  return (
    // `Column(mainAxisSize: min, stretch, spacing: spacingBig)`.
    <div className={styles.page}>
      <RankTopbar data={data} />
      <RankStreakHero weeks={data.streakWeeks} />
      <RankSummarySection data={data} />
      <div className={styles.divider} />
      <NextRankSection rank={data.rank} />
      <LevelUpVideos videos={data.levelUpVideos} />
    </div>
  );
}
