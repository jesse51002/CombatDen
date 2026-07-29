// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_mosaic.dart — `VideosFormat.mosaic`, the densest of the five.
//
// The filter PINS to the top so it stays reachable through a long page, the
// hero spans the full gutter width, and each genre becomes a two-column tile
// grid under an inline band divider.
//
// `SliverPersistentHeader(pinned: true)` ports as `position: sticky`, and the
// scroll container it sticks to is the scaffold's opted-in body scroller
// (../../support/ShowcaseScaffold.tsx) — the same one the topbar scrolls away
// inside, which is what makes the band land against the top of the phone screen
// rather than against the top of the feed. The band keeps a FIXED height for
// Dart's own reason: the strip scrolls sideways inside it, so the tenant's
// genre count never changes how much chrome the page carries.

import { FeaturedVideoCard } from '../FeaturedVideoCard';
import { VideoCarouselSection } from '../VideoCarouselSection';
import { VideosFeedStatus } from '../VideosFeedStatus';
import type { VideosLayoutData } from '../videosLayoutData';
import { sectionTitle } from '../videosLayoutData';
import { VideosScopeTabs } from '../VideosScopeTabs';

import styles from './VideosMosaic.module.css';

export interface VideosMosaicProps {
  data: VideosLayoutData;
}

export function VideosMosaic({ data }: VideosMosaicProps) {
  const { featured } = data;
  return (
    <>
      {/* `SliverPersistentHeader(pinned: true, delegate: _PinnedTabs)`. */}
      <div className={styles.pinned}>
        <VideosScopeTabs data={data} />
      </div>
      {/* `Padding(horizontal: screenHorizontalPadding) > Column(stretch, spacing: spacingBig)`. */}
      <div className={styles.body}>
        {featured !== null && <FeaturedVideoCard video={featured} />}
        {data.sections.map((section) => (
          <VideoCarouselSection
            key={section.genre}
            title={sectionTitle(section)}
            videos={section.videos}
            layout="grid"
          />
        ))}
        {data.isEmpty && <VideosFeedStatus />}
      </div>
    </>
  );
}
