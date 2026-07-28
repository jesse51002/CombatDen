// Ports ../../../../../../CRM/lib/showcase/home/home_not_booked_body.dart — a
// clone of MobileApp's `HomeNotBookedBody` — and, for the parts that clone
// dropped, `MobileApp/lib/features/home/presentation/widgets/home_body.dart`
// itself: the topbar, the PINNED date row, and the day-by-day schedule board.
//
// THE DART CLONE FLATTENED THE BOARD; THIS ONE PUTS IT BACK. The showcase
// original rendered one day under a fixed three-pill strip and let the phone
// frame clip whatever ran past the bottom, because the preview was a single
// viewport with no scroller. The real screen is a `CustomScrollView` whose date
// row is a `SliverPersistentHeader(pinned: true)` over one `DayClassGroup` per
// window day, and that shape is reachable now: the scaffold scrolls
// (`bodyScroll` on ../support/ShowcaseScaffold.tsx) and `position: sticky` is
// what a pinned sliver is.
//
// The pinning is the load-bearing half. A schedule that merely scrolls is a
// list; a schedule whose date row stays put while the days move under it is the
// member app — and it is the piece a layout-variant pass has something to
// rearrange.
//
// WHY FIVE DAYS AND NOT FOURTEEN. `HomeState.initialWindowDays` is 14 and the
// board extends to 60 as the member scrolls — a server-paged window this
// preview has no server for. Five days is four viewports of real board: enough
// to show the screen is deep, short enough that stepping to the next preview
// screen never means scrolling past forty identical rows.

import type { ReactNode } from 'react';

import type { ShowcaseClassInfo } from '../showcaseContent';

import { DateTab } from './DateTab';
import { DayClassGroup } from './DayClassGroup';
import styles from './HomeNotBookedBody.module.css';
import { dayAt, formatDayLabel } from './homeScheduleGenerator';

/**
 * The preview's own window: one date pill and one day group per day. See the
 * header for why it is five rather than the app's 14.
 */
const VISIBLE_DAYS = 5;

/** `0, 1, … VISIBLE_DAYS - 1` — the day offsets the board covers. */
const DAY_OFFSETS: readonly number[] = Object.freeze(
  Array.from({ length: VISIBLE_DAYS }, (_, offset) => offset),
);

export interface HomeNotBookedBodyProps {
  /** The branded topbar (gym logo + name + info bar). */
  topbar: ReactNode;
  /** The selected gym's classes to preview; null falls back to the samples. */
  classes?: readonly ShowcaseClassInfo[] | null | undefined;
}

export function HomeNotBookedBody({ topbar, classes }: HomeNotBookedBodyProps) {
  return (
    <div className={styles.body}>
      {topbar}
      <PinnedDateStrip />
      {DAY_OFFSETS.map((offset) => (
        <DayClassGroup key={offset} day={dayAt(offset, classes)} showBookings={false} />
      ))}
    </div>
  );
}

/**
 * `PinnedDateRowDelegate` over `DateRow` — one pill per window day, pinned to
 * the top of the scroller.
 *
 * TODAY STAYS SELECTED. The real row re-selects as the member scrolls past each
 * day heading, which it measures with a `GlobalKey` per day and a scroll
 * listener. Reproducing that here would mean writing state on every scroll frame
 * to drive an affordance nobody can tap in a phone mock, so the pills are labels
 * — the same call ../rewards/RewardsTabs.tsx and ../videos/VideoCategoryTabs.tsx
 * make for their own rows.
 */
function PinnedDateStrip() {
  return (
    <div className={styles.dateStrip}>
      <div className={styles.dateRow}>
        {DAY_OFFSETS.map((offset) => (
          <DateTab key={offset} label={formatDayLabel(offset)} isSelected={offset === 0} />
        ))}
      </div>
    </div>
  );
}
