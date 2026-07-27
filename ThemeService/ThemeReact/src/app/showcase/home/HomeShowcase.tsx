// Ports ../../../../../../CRM/lib/showcase/home_showcase.dart — an exact visual
// clone of the member app's HOME screen (`HomeScreen` -> `HomeNotBookedBody`):
// the big-logo topbar, a pinned date strip, and the day-by-day class schedule
// under the themed bottom nav.
//
// A STATIC surface: nothing here animates, which is why it takes no loop knobs.
// `gymName` / `gymLogoSrc` are the HOST's gym identity and are NOT customization
// slots — a theme pick must never rename the mock's gym. `themeTabPreview`
// selects the topbar's middle logo rung (see ../support/ShowcaseTopbar.tsx).

import type { ShowcaseClassInfo } from '../showcaseContent';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';

import { HomeNotBookedBody } from './HomeNotBookedBody';

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
  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bottomNav={<ShowcaseBottomNav selected="home" />}
    >
      <HomeNotBookedBody
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
