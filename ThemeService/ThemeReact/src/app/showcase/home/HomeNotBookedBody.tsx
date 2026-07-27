// Ports ../../../../../../CRM/lib/showcase/home/home_not_booked_body.dart — a
// clone of MobileApp's `HomeNotBookedBody`, made STATIC for the preview: the
// topbar, a fixed (non-scrolling) date strip, and the first day's schedule.
//
// The real screen scrolls vertically and its date strip scrolls horizontally;
// the showcase removes both. The content is laid out once at its natural height
// and the phone frame clips whatever runs past the bottom — which is what Dart
// spells as `ClipRect(OverflowBox(minHeight: 0, maxHeight: infinity,
// alignment: topCenter, …))` and CSS gets from a plain block in an
// `overflow: hidden` box.

import type { ReactNode } from 'react';

import type { ShowcaseClassInfo } from '../showcaseContent';

import { DateTab } from './DateTab';
import { DayClassGroup } from './DayClassGroup';
import styles from './HomeNotBookedBody.module.css';
import { dayAt, formatDayLabel } from './homeScheduleGenerator';

/**
 * `_kVisibleDateTabs` — how many date pills the static strip shows. Three fits
 * the device width comfortably with no horizontal scroll.
 */
const VISIBLE_DATE_TABS = 3;

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
      <StaticDateStrip />
      <DayClassGroup day={dayAt(0, classes)} showBookings={false} />
    </div>
  );
}

/** `_StaticDateStrip`. */
function StaticDateStrip() {
  return (
    <div className={styles.dateStrip}>
      {Array.from({ length: VISIBLE_DATE_TABS }, (_, i) => (
        <DateTab key={i} label={formatDayLabel(i)} isSelected={i === 0} />
      ))}
    </div>
  );
}
