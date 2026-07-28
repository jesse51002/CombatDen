// Ports ../../../../../../CRM/lib/showcase/home_showcase.dart — an exact visual
// clone of the member app's HOME screen (`HomeScreen` -> `HomeBody`): the
// big-logo topbar, the date rail, and the day-by-day class schedule under the
// themed bottom nav.
//
// A STATIC surface: nothing here animates, which is why it takes no loop knobs.
// It DOES scroll (`bodyScroll`) — the schedule board is a multi-day list on a
// real device, and previewing one clipped day would sell a shorter app than the
// one being licensed. Every arrangement keeps that one scroller, `dayPager`
// included: its pager rides INSIDE it rather than beside it (see
// ./layouts/HomeDayPager.tsx).
//
// WHICH ARRANGEMENT IT RENDERS is the tenant's `home_format` slot, resolved by
// `useFormat` in the store's own order — the preview override, then the theme's
// classified pick, then `agendaList`, the value that ships. The topbar is built
// here and handed DOWN, because it is the same in every arrangement: its own
// layout is the tenant's `app_shell_format`, not home's, so no home layout has
// any business changing what it is given.
//
// `gymName` / `gymLogoSrc` are the HOST's gym identity and are NOT customization
// slots — a theme pick must never rename the mock. `themeTabPreview` selects the
// topbar's middle logo rung (see ../support/ShowcaseTopbar.tsx).

import { FORMAT_SLOTS, HOME_FORMATS, useFormat } from '../formats';
import type { ShowcaseClassInfo } from '../showcaseContent';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';

import { HomeLayoutBody } from './HomeLayoutBody';

// Dummy non-identity data: the streak / points / rank chips in the info bar.
// Gym name + logo come from the host.
const RANK_BADGE_ASSET = 'icon_rank_belt.png' as const;
const STREAK_DAYS = 3;
const POINTS_LABEL = '3.4k';

export interface HomeShowcaseProps {
  gymName?: string;
  /** The host gym's real logo URL. Absent in the public browser. */
  gymLogoSrc?: string | undefined;
  /** The gym's real classes; null falls back to the group defaults. */
  classes?: readonly ShowcaseClassInfo[] | null;
  themeTabPreview?: boolean;
}

export function HomeShowcase({
  gymName = 'Your Gym',
  gymLogoSrc,
  classes,
  themeTabPreview = false,
}: HomeShowcaseProps) {
  const format = useFormat(FORMAT_SLOTS.home, HOME_FORMATS, 'agendaList');
  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll
      bottomNav={<ShowcaseBottomNav selected="home" />}
    >
      <HomeLayoutBody
        format={format}
        classes={classes}
        topbar={
          <ShowcaseTopbar
            mode="bigLogo"
            gymName={gymName}
            logoSrc={gymLogoSrc}
            streakDays={STREAK_DAYS}
            pointsLabel={POINTS_LABEL}
            rankBadgeAsset={RANK_BADGE_ASSET}
            themeTabPreview={themeTabPreview}
          />
        }
      />
    </ShowcaseScaffold>
  );
}
