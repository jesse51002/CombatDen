// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/layouts/
// videos_shorts_column.dart — `VideosFormat.shortsColumn`: one column of poster
// cards.
//
// The genre name rides the top of its first card instead of standing above the
// section, so the page reads as one continuous run of posters — the shape
// members already use for this content elsewhere.
//
// THE ARTWORK IS STILL 16:9. A "tall" card is a card that grew a caption band
// over its image, not an image re-proportioned to portrait: YouTube serves
// thumbnails at a fixed aspect, and re-cropping them would lose the subject on
// every card at once. See ../VideoCarouselCard.module.css.

import { FeaturedVideoCard } from '../FeaturedVideoCard';
import { VideoCarouselSection } from '../VideoCarouselSection';
import { VideosFeedStatus } from '../VideosFeedStatus';
import type { VideosLayoutData } from '../videosLayoutData';
import { sectionTitle } from '../videosLayoutData';
import { VideosScopeTabs } from '../VideosScopeTabs';

import styles from './VideosShortsColumn.module.css';

export interface VideosShortsColumnProps {
  data: VideosLayoutData;
}

export function VideosShortsColumn({ data }: VideosShortsColumnProps) {
  const { featured } = data;
  return (
    <>
      <VideosScopeTabs data={data} />
      {/* `Padding(horizontal: screenHorizontalPadding) > _Column`. */}
      <div className={styles.body}>
        {featured !== null && <FeaturedVideoCard video={featured} />}
        {data.sections.map((section) => (
          <VideoCarouselSection
            key={section.genre}
            title={sectionTitle(section)}
            videos={section.videos}
            layout="tall"
          />
        ))}
        {data.isEmpty && <VideosFeedStatus />}
      </div>
    </>
  );
}
