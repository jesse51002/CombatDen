// Ports MobileApp/lib/features/home/presentation/layouts/home_layout_data.dart.
//
// Everything a home layout needs, gathered once so the five layouts share one
// payload instead of each re-deriving it.
//
// EVERY LAYOUT RECEIVES THE SAME DATA and must render every element it implies.
// A layout may move them and change their prominence; it may not drop one, add
// one, or reach for anything not in here — there is no repository, no fetch and
// no clock behind this type, which is what makes "no variant reaches data the
// shipped screen did not have" structurally true rather than argued.
//
// Dart's `HomeLayoutData` also carries `booked` / `hasError` / `classes == null`
// — home's two pages and the three not-loaded states. THIS PREVIEW HAS NEITHER.
// The showcase renders the not-booked page against content the ladder in
// ../../useShowcaseContent.ts has already resolved (real → fetched → bundled),
// so the schedule is always loaded and never booked. Adding a state here would
// be inventing a screen the browser does not have, which is the same rule the
// formats themselves obey.

import type { ReactNode } from 'react';

import type { ShowcaseClassInfo } from '../../showcaseContent';

/**
 * The preview's own window: one date pill and one day group per day.
 *
 * WHY FIVE DAYS AND NOT FOURTEEN. `HomeState.initialWindowDays` is 14 and the
 * board extends to 60 as the member scrolls — a server-paged window this
 * preview has no server for. Five days is four viewports of real board: enough
 * to show the screen is deep, short enough that stepping to the next preview
 * screen never means scrolling past forty identical rows.
 */
export const VISIBLE_DAYS = 5;

/** `0, 1, … VISIBLE_DAYS - 1` — the day offsets the board covers. */
export const DAY_OFFSETS: readonly number[] = Object.freeze(
  Array.from({ length: VISIBLE_DAYS }, (_, offset) => offset),
);

export interface HomeLayoutProps {
  /** The branded topbar (gym logo + name + info bar). Every format renders it. */
  topbar: ReactNode;
  /** The selected gym's classes to preview; null falls back to the samples. */
  classes?: readonly ShowcaseClassInfo[] | null | undefined;
}
