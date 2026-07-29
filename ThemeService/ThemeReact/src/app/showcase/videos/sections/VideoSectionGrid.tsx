// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// sections/video_section_grid.dart — a genre section as a two-column tile grid
// under a band-divider header, with the "view all" action taking the last cell.
//
// THE ACTION IS A CELL, NOT A FOOTER. Dart appends it to the same `cells` list
// the cards fill, so it flows into whichever slot comes next and the grid never
// grows a ragged trailing row with a control bolted under it.
//
// Dart lays the cells out as rows of two rather than as a `GridView` so the
// section keeps its natural height inside the page's own scroll; CSS grid is
// the same thing without the manual row loop, and `align-items: start` is
// Dart's `crossAxisAlignment: start` on each row.

import type { ShowcaseVideo } from '../../showcaseContent';
import { PART_ATTR, VIDEO_PARTS } from '../videoParts';
import { VideoCarouselCard } from '../VideoCarouselCard';
import { VideoViewAllAction } from '../VideoViewAllAction';

import { VideoSectionHeader } from './VideoSectionHeader';
import styles from './VideoSectionGrid.module.css';

export interface VideoSectionGridProps {
  title: string;
  videos: readonly ShowcaseVideo[];
}

export function VideoSectionGrid({ title, videos }: VideoSectionGridProps) {
  return (
    // `Column(stretch, spacing: spacingLarge)`.
    <section className={styles.section} {...{ [PART_ATTR]: VIDEO_PARTS.section }}>
      <VideoSectionHeader title={title} style="divider" showViewAll={false} />
      <div className={styles.grid}>
        {videos.map((video) => (
          <VideoCarouselCard key={video.videoId} video={video} size="tile" />
        ))}
        <VideoViewAllAction style="tile" />
      </div>
    </section>
  );
}
