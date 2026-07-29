// Ports MobileApp/lib/features/home/presentation/layouts/home_day_pager.dart.
//
// `HomeFormat.dayPager` — one day per swipe.
//
// The date rail stops being a scroll shortcut and BECOMES THE PRIMARY CONTROL:
// it drives a horizontal pager, one day per page, and the classes get the room
// to be wide media cards. Trades cross-day scanning for a much stronger
// single-day read.
//
// THE RAIL IS LIVE HERE AND NOWHERE ELSE, and that is the arrangement rather
// than a new feature. Dart's rail is tappable in all five formats (it scrolls
// the vertical scroller to the day); this preview keeps the shipped board's
// static rail for the four vertical formats — see ../DateRow.tsx — because
// there is no scroll-spy behind it. In `dayPager` the rail is the only way to
// reach day two, so wiring it is what makes the arrangement the thing it is.
// The ELEMENT SET is unchanged either way: the same five pills, the same
// labels, exactly one selected.
//
// WHY NOT `NestedScrollView`. Dart needs one because the header must scroll
// away above a pager that owns its own vertical scrolling, and the two
// scrollers have to hand off. The web gets that hand-off for free from one
// scroller: the pager is a plain horizontal scroll-snap strip whose height is
// its content, sitting INSIDE the scaffold's vertical scroller, so the topbar
// scrolls away, the rail sticks, and the day's classes scroll — all on the same
// axis, with no coordination to write.

import { useRef, useState } from 'react';

import { DateRow } from '../DateRow';
import { DayClassGroup } from '../DayClassGroup';
import { dayAt } from '../homeScheduleGenerator';

import { DAY_OFFSETS } from './homeLayout';
import type { HomeLayoutProps } from './homeLayout';
import styles from './HomeDayPager.module.css';

export function HomeDayPager({ topbar, classes }: HomeLayoutProps) {
  const [currentDayIndex, setCurrentDayIndex] = useState(0);
  const pagerRef = useRef<HTMLDivElement | null>(null);

  // `_onDateTap` — `_pageController.animateToPage(index, easeOut)`. A ref write
  // and a `setState` in an EVENT handler, which is the one place this package's
  // React Compiler rules allow either.
  function onDateTap(index: number): void {
    setCurrentDayIndex(index);
    const pager = pagerRef.current;
    if (pager === null) return;
    pager.scrollTo({ left: index * pager.clientWidth, behavior: 'smooth' });
  }

  // `PageView.onPageChanged` — a swipe re-selects the rail.
  function onPagerScroll(event: React.UIEvent<HTMLDivElement>): void {
    const pager = event.currentTarget;
    if (pager.clientWidth === 0) return;
    const index = Math.round(pager.scrollLeft / pager.clientWidth);
    if (index !== currentDayIndex) setCurrentDayIndex(index);
  }

  return (
    <div className={styles.body}>
      {topbar}
      <DateRow
        dayOffsets={DAY_OFFSETS}
        currentDayIndex={currentDayIndex}
        onDateTap={onDateTap}
      />
      <div className={styles.pager} ref={pagerRef} onScroll={onPagerScroll}>
        {DAY_OFFSETS.map((offset) => (
          <div className={styles.page} key={offset}>
            <DayClassGroup
              day={dayAt(offset, classes)}
              showBookings={false}
              itemLayout="imageTop"
            />
          </div>
        ))}
      </div>
    </div>
  );
}
