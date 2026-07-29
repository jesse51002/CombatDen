// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// rank_summary/timeframe_selector.dart (and, for the pill itself,
// `shared/widgets/pills/timeframe_pill.dart`) — the 1W / 1M / 1Y / ALL range
// selector for the rank graph, in the four shapes the arrangements need.
//
// THE PILLS DO NOT WINDOW ANYTHING, and that is the island's rule rather than a
// gap: every showcase surface is a preview inside a phone frame that takes no
// input, which is why ../rewards/RewardsTabs.tsx dropped its callbacks and
// ../videos/VideoCategoryTabs.tsx renders labels. ALL is the pinned selection
// (`SHOWCASE_TIMEFRAME_INDEX`), and it is the one the plot is drawn from, so
// the highlighted pill always names the window on screen.
//
// The four values are the same four in every layout — the Dart's own `_kRanges`
// is a file-level const for exactly that reason. A layout moves the row,
// stacks it, or stretches it; it never drops a range.

import { cx } from '../cx';

import { RANK_PART } from './rankParts';
import styles from './TimeframeSelector.module.css';
import { RANK_TIMEFRAMES, SHOWCASE_TIMEFRAME_INDEX } from './mockRankProgress';

/** `TimeframeLayout`. */
export type TimeframeLayout = 'pills' | 'inline' | 'segmented' | 'tile';

const LAYOUT_CLASS: Readonly<Record<TimeframeLayout, string | undefined>> = Object.freeze({
  pills: styles.pills,
  inline: styles.inline,
  segmented: styles.segmented,
  tile: styles.tile,
});

export interface TimeframeSelectorProps {
  /** `pills` is the loose centred row that ships. */
  layout?: TimeframeLayout;
}

export function TimeframeSelector({ layout = 'pills' }: TimeframeSelectorProps) {
  if (layout === 'tile') {
    // `_tile()` — two by two. Rows rather than a wrap: a pill sizes to its
    // label on an unbounded main axis, which is what keeps the four reading as
    // four chips inside a board cell rather than four full-width bands.
    const rows: (typeof RANK_TIMEFRAMES)[] = [];
    for (let i = 0; i < RANK_TIMEFRAMES.length; i += 2) {
      rows.push(RANK_TIMEFRAMES.slice(i, i + 2));
    }
    return (
      <div className={styles.tile}>
        {rows.map((row) => (
          <div key={row[0]?.label ?? ''} className={styles.tileRow}>
            {row.map((entry) => (
              <Pill key={entry.label} label={entry.label} />
            ))}
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className={cx(styles.row, LAYOUT_CLASS[layout])}>
      {RANK_TIMEFRAMES.map((entry) => (
        <Pill key={entry.label} label={entry.label} />
      ))}
    </div>
  );
}

/**
 * `TimeframePill` — `Container(height: pillHeightMd, padding: horizontal:
 * screenHorizontalPadding, borderRadius: radiusBig)` over `Text(h2)`.
 *
 * An inactive pill has NO border at all (Dart passes `null`), which is what
 * makes the selected one read as the only chip in the row.
 */
function Pill({ label }: { label: string }) {
  const isActive = label === RANK_TIMEFRAMES[SHOWCASE_TIMEFRAME_INDEX]?.label;
  return (
    <span
      className={cx(styles.pill, isActive && styles.pillActive)}
      data-rank-part={RANK_PART.timeframePill}
      data-rank-active={isActive ? '' : undefined}
    >
      {label}
    </span>
  );
}
