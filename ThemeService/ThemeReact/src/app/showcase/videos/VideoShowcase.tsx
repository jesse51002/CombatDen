// Ports ../../../../../../MobileApp/lib/features/videos/presentation/screens/
// videos_screen.dart — a visual clone of the member app's VIDEOS tab: the
// name-only topbar over whichever arrangement the tenant's `videos_format`
// selects (./VideosFeedBody.tsx).
//
// NO DART SHOWCASE COUNTERPART. The other surfaces in this island port
// `CRM/lib/showcase/*.dart`; the Flutter preview never carried Videos, so this
// is a first port straight from the member app — which is why the header points
// at `MobileApp/` rather than at a showcase clone.
//
// THE SCREEN OWNS THE SHELL, THE ARRANGEMENT OWNS THE FEED. The topbar, the
// bottom nav and the scroller are identical in all five values, exactly as they
// are in Dart: a format arranges videos, so everything that is not videos stays
// here. The filter pills are NOT in that set — `mosaic` pins them and `tagRail`
// turns them into a rail — so they live inside the arrangement.
//
// A STATIC, SCROLLING SURFACE. The real screen is a `CustomScrollView` and so is
// this one (`bodyScroll` on ../support/ShowcaseScaffold.tsx): a feed is the one
// thing in the member app that cannot be shown in a single viewport, and
// clipping it would preview a shorter app than the one being sold. Nothing here
// animates, so the screen takes no loop knobs.
//
// THE STATES THE REAL SCREEN HAS AND THIS ONE DOES NOT. `videos_screen.dart`
// branches over loading / error / empty because it awaits a portal fetch. The
// preview resolves its feed synchronously from bundled constants
// (../useShowcaseContent.ts), so the loading and retryable-error branches have
// no reachable input here and are not ported — see ./VideosFeedStatus.tsx.
//
// WHAT IS THE GYM'S AND WHAT IS THE MEMBER'S. `gymName` / `gymLogoSrc` are the
// HOST's gym identity and are NOT customization slots. The streak, points and
// rank badge in the topbar are PER-MEMBER chrome and stay sample data, exactly
// as ../RewardsShowcase.tsx keeps them when a gym's real rewards are injected.

import type { ShowcaseVideo } from '../showcaseContent';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';

import styles from './VideoShowcase.module.css';
import { VideosFeedBody } from './VideosFeedBody';
import { videosLayoutData } from './videosLayoutData';

/** `VideosScreen`'s own default gym name, matching every other surface here. */
const DEFAULT_GYM_NAME = 'Your Gym';

// Dummy non-identity data: the streak / points / rank chips in the info bar,
// the same sample values ../home/HomeShowcase.tsx carries.
const RANK_BADGE_ASSET = 'icon_rank_belt.png' as const;
const STREAK_DAYS = 3;
const POINTS_LABEL = '3.4k';

// Re-exported from where it has always been imported: the tab labels are part
// of the payload every arrangement is handed, so the derivation moved to
// ./videosLayoutData.ts with the rest of it.
export { videoTabLabels } from './videosLayoutData';

export interface VideoShowcaseProps {
  /** The host gym's name. There is no gym in this browser. */
  gymName?: string;
  /** The host gym's real logo URL. Absent here. */
  gymLogoSrc?: string | undefined;
  /** The resolved feed for the previewed theme's category. */
  videos: readonly ShowcaseVideo[];
}

export function VideoShowcase({
  gymName = DEFAULT_GYM_NAME,
  gymLogoSrc,
  videos,
}: VideoShowcaseProps) {
  const data = videosLayoutData(videos);

  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll
      bottomNav={<ShowcaseBottomNav selected="videos" />}
    >
      {/* `CustomScrollView`'s sliver list, as one column inside the scroller. */}
      <div className={styles.feed}>
        <ShowcaseTopbar
          mode="nameOnly"
          gymName={gymName}
          logoSrc={gymLogoSrc}
          streakDays={STREAK_DAYS}
          pointsLabel={POINTS_LABEL}
          rankBadgeAsset={RANK_BADGE_ASSET}
        />
        <VideosFeedBody data={data} />
      </div>
    </ShowcaseScaffold>
  );
}
