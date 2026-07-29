// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// rank_summary/rank_summary_section.dart — the current rank over its plot over
// the range selector, the block `sparkleStack` opens the rank half of the
// screen with.
//
// IT IS A GROUPING, NOT A WIDGET. `sparkleStack` is the only arrangement that
// keeps the three together; the other four split them (`beltHero` sends the
// header to the top of the screen and the plot below a rule, `statTiles` puts
// the header and the selector in separate board cells). That is exactly why the
// three are separate components and this file only stacks them.

import { RankHeader } from './RankHeader';
import { RatingGraph } from './RatingGraph';
import styles from './RankSummarySection.module.css';
import { TimeframeSelector } from './TimeframeSelector';
import type { RankLayoutData } from './rankLayoutData';

export function RankSummarySection({ data }: { data: RankLayoutData }) {
  return (
    // `Column(mainAxisSize: min, center, spacing: spacingLarge)`.
    <div className={styles.summary}>
      <RankHeader rankTitle={data.rank.name} rankSubtitle={data.rank.subLabel} />
      <RatingGraph points={data.points} />
      <TimeframeSelector />
    </div>
  );
}
