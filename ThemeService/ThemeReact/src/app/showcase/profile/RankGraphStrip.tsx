// Ports ../../../../../../MobileApp/lib/features/profile/presentation/layouts/
// parts/rank_graph_strip.dart — the graph on the seam between `splitRank`'s
// "now" and "next" halves: the range selector on a header line, the plot as a
// short strip under it.
//
// OPEN, AND STAYS OPEN. Dart holds `_open` as local state so the member can
// collapse the strip; collapsing is THEIR choice, not the layout's, which is
// why nothing on the screen starts hidden. This island takes no input at all
// (../rewards/RewardsTabs.tsx dropped its callbacks, ./TimeframeSelector.tsx's
// pills do not window anything), so the chevron renders as the affordance the
// phone has and the strip renders in the state the phone opens in. Wiring it
// would be inventing an interaction for a screenshot, and holding it closed
// would hide the plot the arrangement exists to place.
//
// THE CHEVRON IS ../support/icons.tsx's `ExpandMoreIcon`, ROTATED. Dart names
// `Symbols.expand_less_sharp` and `Symbols.expand_more_sharp`; they are one
// glyph and its mirror, so the open state turns the existing icon rather than
// adding a second nearly-identical path to the shared icon set.

import { ExpandMoreIcon } from '../support/icons';

import { RatingGraph } from './RatingGraph';
import styles from './RankGraphStrip.module.css';
import type { ShowcaseRankPoint } from './mockRankProgress';
import { TimeframeSelector } from './TimeframeSelector';

export function RankGraphStrip({ points }: { points: readonly ShowcaseRankPoint[] }) {
  return (
    // `Column(stretch, mainAxisSize: min, spacing: spacingMedium)`.
    <div className={styles.strip}>
      {/* `Padding(horizontal: screenHorizontalPadding) > Row(spacing: spacingMedium)`. */}
      <div className={styles.header}>
        <div className={styles.selector}>
          <TimeframeSelector layout="inline" />
        </div>
        {/* `Icon(expand_less_sharp, size: iconSizeMd, color: text2nd)`. */}
        <ExpandMoreIcon className={styles.chevron} />
      </div>
      <RatingGraph points={points} size="sm" />
    </div>
  );
}
