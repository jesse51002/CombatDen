// Ports MobileApp/lib/features/home/presentation/layouts/home_time_spine.dart.
//
// `HomeFormat.timeSpine` — the day reads as a timetable.
//
// The time leaves the meta column and becomes a left gutter, with a vertical
// rule running down every row so consecutive classes read as one continuous
// spine; the thumbnail demotes to a small square. What a member with three
// classes in one evening actually needs.

import { HomeScheduleScroll } from './HomeScheduleScroll';
import type { HomeLayoutProps } from './homeLayout';

export function HomeTimeSpine({ topbar, classes }: HomeLayoutProps) {
  return <HomeScheduleScroll topbar={topbar} classes={classes} itemLayout="spine" />;
}
