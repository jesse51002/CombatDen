// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_tag_rail.dart — `VideosFormat.tagRail`: the filter leaves the top and
// becomes a rail down the left, pinned so it stays reachable the whole way
// down.
//
// Content is one narrower column beside it. This is the value for a tenant
// whose feed carries enough genres that a pill strip across the top stops being
// readable.
//
// `SliverCrossAxisGroup` ports as a flex ROW, and `SliverPersistentHeader(
// pinned: true)` inside its constrained cross axis as a `position: sticky`
// column of fixed width and height. `align-items: flex-start` is what keeps the
// rail from stretching to the content's height — a sticky element that already
// fills its container has nothing to stick within.

import { FeaturedVideoCard } from '../FeaturedVideoCard';
import { VideoCarouselSection } from '../VideoCarouselSection';
import { VideosFeedStatus } from '../VideosFeedStatus';
import type { VideosLayoutData } from '../videosLayoutData';
import { sectionTitle } from '../videosLayoutData';
import { VideosScopeTabs } from '../VideosScopeTabs';

import styles from './VideosTagRail.module.css';

export interface VideosTagRailProps {
  data: VideosLayoutData;
}

export function VideosTagRail({ data }: VideosTagRailProps) {
  const { featured } = data;
  return (
    // `SliverCrossAxisGroup`.
    <div className={styles.split}>
      {/* `SliverConstrainedCrossAxis(112) > SliverPersistentHeader(pinned: true)`. */}
      <div className={styles.rail}>
        <VideosScopeTabs data={data} axis="vertical" />
      </div>
      {/* `SliverCrossAxisExpanded > Padding(left: spacingMedium, right: screenHorizontalPadding)`. */}
      <div className={styles.content}>
        {featured !== null && <FeaturedVideoCard video={featured} />}
        {data.sections.map((section) => (
          <VideoCarouselSection
            key={section.genre}
            title={sectionTitle(section)}
            videos={section.videos}
            layout="stack"
          />
        ))}
        {data.isEmpty && <VideosFeedStatus />}
      </div>
    </div>
  );
}
