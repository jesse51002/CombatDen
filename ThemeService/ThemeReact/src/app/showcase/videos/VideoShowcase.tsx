// Ports ../../../../../../MobileApp/lib/features/videos/presentation/screens/
// videos_screen.dart + widgets/videos_feed_body.dart — a visual clone of the
// member app's VIDEOS tab: the name-only topbar, the genre pill strip, a
// featured hero, then one carousel per genre in the feed.
//
// NO DART SHOWCASE COUNTERPART. The other surfaces in this island port
// `CRM/lib/showcase/*.dart`; the Flutter preview never carried Videos, so this
// is a first port straight from the member app — which is why the header points
// at `MobileApp/` rather than at a showcase clone.
//
// A STATIC, SCROLLING SURFACE. The real screen is a `SingleChildScrollView` and
// so is this one (`bodyScroll` on ../support/ShowcaseScaffold.tsx): a feed is
// the one thing in the member app that cannot be shown in a single viewport,
// and clipping it would preview a shorter app than the one being sold. Nothing
// here animates, so the screen takes no loop knobs.
//
// THE STATES THE REAL SCREEN HAS AND THIS ONE DOES NOT. `videos_screen.dart`
// branches over loading / error / empty because it awaits a portal fetch. The
// preview resolves its feed synchronously from bundled constants
// (../useShowcaseContent.ts), so the loading and retryable-error branches have
// no reachable input here and are not ported — an unreachable spinner is a lie
// about what the phone does. The EMPTY branch is kept, because it is reachable:
// a host that injects a real gym with no videos hits it.
//
// WHAT IS THE GYM'S AND WHAT IS THE MEMBER'S. `gymName` / `gymLogoSrc` are the
// HOST's gym identity and are NOT customization slots. The streak, points and
// rank badge in the topbar are PER-MEMBER chrome and stay sample data, exactly
// as ../RewardsShowcase.tsx keeps them when a gym's real rewards are injected.

import type { ShowcaseVideo } from '../showcaseContent';
import { ShowcaseBottomNav } from '../support/ShowcaseBottomNav';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';
import { ShowcaseTopbar } from '../support/ShowcaseTopbar';

import { FeaturedVideoCard } from './FeaturedVideoCard';
import { VideoCategoryTabs } from './VideoCategoryTabs';
import { VideoCarouselSection } from './VideoCarouselSection';
import styles from './VideoShowcase.module.css';
import { featuredVideo, genreLabel, genresInFeed, genreSections } from './videoSelectors';

/** `VideosScreen`'s own default gym name, matching every other surface here. */
const DEFAULT_GYM_NAME = 'Your Gym';

// Dummy non-identity data: the streak / points / rank chips in the info bar,
// the same sample values ../home/HomeShowcase.tsx carries.
const RANK_BADGE_ASSET = 'icon_rank_belt.png' as const;
const STREAK_DAYS = 3;
const POINTS_LABEL = '3.4k';

/**
 * `tabGenres = [null, ...genres]` — "All" is this screen, so index 0 is always
 * the selected tab in a preview that cannot navigate.
 */
export function videoTabLabels(videos: readonly ShowcaseVideo[]): readonly string[] {
  return ['All', ...genresInFeed(videos).map(genreLabel)];
}

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
  const featured = featuredVideo(videos);
  const sections = genreSections(videos);

  return (
    <ShowcaseScaffold
      horizontalPadding="none"
      bodyScroll
      bottomNav={<ShowcaseBottomNav selected="videos" />}
    >
      {/* `Column(crossAxisAlignment: stretch)` inside the screen's scroller. */}
      <div className={styles.feed}>
        <ShowcaseTopbar
          mode="nameOnly"
          gymName={gymName}
          logoSrc={gymLogoSrc}
          streakDays={STREAK_DAYS}
          pointsLabel={POINTS_LABEL}
          rankBadgeAsset={RANK_BADGE_ASSET}
        />
        <VideoCategoryTabs tabs={videoTabLabels(videos)} selectedIndex={0} />

        {featured === null && sections.length === 0 ? (
          // `VideosFeedBody`'s own empty state, verbatim.
          <p className={styles.empty}>Nothing here yet.</p>
        ) : (
          // `Column(stretch, spacing: spacingBig)`.
          <div className={styles.body}>
            {featured !== null && (
              // `_PaddedSection(horizontal: screenHorizontalPadding)`.
              <div className={styles.heroInset}>
                <FeaturedVideoCard video={featured} />
              </div>
            )}
            {sections.map((section) => (
              <VideoCarouselSection
                key={section.genre}
                title={genreLabel(section.genre)}
                videos={section.videos}
              />
            ))}
          </div>
        )}
      </div>
    </ShowcaseScaffold>
  );
}
