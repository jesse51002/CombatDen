// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_carousel_rows.dart — `VideosFormat.carouselRows`, the arrangement that
// ships today.
//
// Pill strip, a featured hero in the screen gutter, then one horizontally
// scrolling row per genre. It reproduces this island's previous `VideoShowcase`
// body value for value, so a tenant whose theme carries no `videos_format` — or
// one classified into the default — sees no change at all. That is not a
// courtesy: ../__tests__/videosFormats.test.tsx renders this arrangement and
// diffs its markup against a fixture captured from the screen BEFORE the
// arrangements existed, so a drift here fails rather than ships.

import { FeaturedVideoCard } from '../FeaturedVideoCard';
import { VideoCarouselSection } from '../VideoCarouselSection';
import { VideosFeedStatus } from '../VideosFeedStatus';
import type { VideosLayoutData } from '../videosLayoutData';
import { sectionTitle } from '../videosLayoutData';
import { VideosScopeTabs } from '../VideosScopeTabs';

import styles from './VideosCarouselRows.module.css';

export interface VideosCarouselRowsProps {
  data: VideosLayoutData;
}

export function VideosCarouselRows({ data }: VideosCarouselRowsProps) {
  const { featured } = data;
  return (
    // A fragment, not a box: the arrangement's children are laid out by the
    // screen's own feed column (../VideoShowcase.module.css), exactly as Dart's
    // slivers are laid out by the screen's `CustomScrollView`.
    <>
      <VideosScopeTabs data={data} />
      {/* `Column(stretch, spacing: spacingBig)`. */}
      <div className={styles.body}>
        {featured !== null && (
          // `Padding(horizontal: screenHorizontalPadding)`.
          <div className={styles.heroInset}>
            <FeaturedVideoCard video={featured} />
          </div>
        )}
        {data.sections.map((section) => (
          <VideoCarouselSection
            key={section.genre}
            title={sectionTitle(section)}
            videos={section.videos}
          />
        ))}
        {data.isEmpty && <VideosFeedStatus />}
      </div>
    </>
  );
}
