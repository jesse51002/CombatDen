// Ports MobileApp/lib/features/home/presentation/layouts/home_next_up_hero.dart.
//
// `HomeFormat.nextUpHero` — what is next, then everything else.
//
// The date rail becomes a segmented control that scrolls away with the content
// rather than pinning, and the rest of the schedule collapses to dense rows.
// The value that best serves the "before class, in a hurry" moment.
//
// ONE KNOB OF THE DART'S FOUR HAS NOTHING TO ACT ON HERE. Dart also passes
// `headerBleed: true`, which runs the UPCOMING-SESSIONS CARD edge to edge — and
// that card belongs to home's BOOKED page (`HomeLayoutData.booked`), which this
// preview does not have (see ./homeLayout.ts). The bleed is therefore a no-op
// rather than a dropped feature: there is no hero card on the not-booked page
// to bleed, in this arrangement or in the one that ships. Adding one would be
// inventing a screen, which is the exact thing a format may not do.
//
// The docs' sketch also drops the class thumbnails and the gym mark here. Both
// stay: removing an element is the one thing a format may not do, and the gate
// in ../__tests__/homeFormats.test.tsx enforces it.

import { HomeScheduleScroll } from './HomeScheduleScroll';
import type { HomeLayoutProps } from './homeLayout';

export function HomeNextUpHero({ topbar, classes }: HomeLayoutProps) {
  return (
    <HomeScheduleScroll
      topbar={topbar}
      classes={classes}
      itemLayout="dense"
      pinDateRow={false}
      dateTabStyle="segmented"
    />
  );
}
