// Ports MobileApp/lib/features/home/presentation/layouts/home_board_grid.dart.
//
// `HomeFormat.boardGrid` — the densest read per scroll.
//
// Each day is a band header over a two-up card grid. Buys the most classes per
// screen and pays for it in time hierarchy: two classes side by side no longer
// read as "this one, then that one".

import { HomeScheduleScroll } from './HomeScheduleScroll';
import type { HomeLayoutProps } from './homeLayout';

export function HomeBoardGrid({ topbar, classes }: HomeLayoutProps) {
  return <HomeScheduleScroll topbar={topbar} classes={classes} grid />;
}
