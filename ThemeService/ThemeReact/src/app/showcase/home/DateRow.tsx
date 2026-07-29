// Ports MobileApp/lib/features/home/presentation/widgets/class_schedule/
// date_row.dart (+ `date_row_header_delegate.dart`, whose whole job — put the
// row in a sliver and let the FORMAT decide whether it pins — is `pinned` here).
//
// One pill per window day. Lifted out of the shipped ./HomeNotBookedBody.tsx
// unchanged so all five arrangements share one rail: `agendaList` /
// `timeSpine` / `boardGrid` pin it, `nextUpHero` lets it scroll away as a
// segmented control, and `dayPager` pins it AND drives the pager with it.
//
// WHY `position: sticky` IS THE PIN. A `SliverPersistentHeader(pinned: true)`
// scrolls up with the content until it reaches the top of the scroller and then
// stays while the days move under it; that is what sticky does, and the opaque
// background is what makes it legible (a sliver paints its own box, an
// unstyled sticky element does not).
//
// TODAY STAYS SELECTED UNLESS A FORMAT DRIVES IT. The real row re-selects as
// the member scrolls past each day heading, measured with a `GlobalKey` per day
// and a scroll listener. Reproducing that here would mean writing state on
// every scroll frame to drive an affordance the vertical formats have nothing
// to do with, so their pills stay labels — the same call ../rewards/RewardsTabs.tsx
// and ../videos/VideoCategoryTabs.tsx make for their own rows. `dayPager` is
// the exception, and it is not a new affordance: there the rail IS the control
// (see ./layouts/HomeDayPager.tsx), exactly as in the Dart.

import { cx } from '../cx';

import { DateTab } from './DateTab';
import type { DateTabStyle } from './DateTab';
import styles from './DateRow.module.css';
import { formatDayLabel } from './homeScheduleGenerator';

export interface DateRowProps {
  /** The day offsets the board covers — one pill each. */
  dayOffsets: readonly number[];
  /** Which pill reads as selected. */
  currentDayIndex: number;
  /** `SliverPersistentHeader(pinned:)`. */
  pinned?: boolean;
  /** How the selected day marks itself. Presentation only. */
  tabStyle?: DateTabStyle;
  /** Set only by the format that makes the rail its primary control. */
  onDateTap?: ((index: number) => void) | undefined;
}

export function DateRow({
  dayOffsets,
  currentDayIndex,
  pinned = true,
  tabStyle = 'underline',
  onDateTap,
}: DateRowProps) {
  return (
    <div className={cx(styles.dateStrip, !pinned && styles.unpinned)}>
      <div className={styles.dateRow}>
        {dayOffsets.map((offset) => (
          <DateTab
            key={offset}
            label={formatDayLabel(offset)}
            isSelected={offset === currentDayIndex}
            style={tabStyle}
            onTap={onDateTap === undefined ? undefined : () => { onDateTap(offset); }}
          />
        ))}
      </div>
    </div>
  );
}
