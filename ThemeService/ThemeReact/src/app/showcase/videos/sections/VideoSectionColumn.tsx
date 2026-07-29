// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// sections/video_section_column.dart — a genre section as one vertical column
// of width-filling cards, with the "view all" action as a row closing it.
//
// NO HORIZONTAL SCROLLING: every card in the section is reachable by the same
// vertical gesture that moves the page. That is the whole point of the shape,
// and it is why `editorialStack` — the arrangement that promises no sideways
// scrolling anywhere — is built out of it.
//
// The section does NOT inset itself; the arrangement placing it decides whether
// it sits in the screen gutter or in a narrower column beside a rail.

import type { ShowcaseVideo } from '../../showcaseContent';
import { PART_ATTR, VIDEO_PARTS } from '../videoParts';
import { VideoCarouselCard } from '../VideoCarouselCard';
import { VideoViewAllAction } from '../VideoViewAllAction';

import { VideoSectionHeader } from './VideoSectionHeader';
import styles from './VideoSectionColumn.module.css';

export interface VideoSectionColumnProps {
  title: string;
  videos: readonly ShowcaseVideo[];
}

export function VideoSectionColumn({ title, videos }: VideoSectionColumnProps) {
  return (
    // `Column(stretch, spacing: spacingLarge)`.
    <section className={styles.section} {...{ [PART_ATTR]: VIDEO_PARTS.section }}>
      <VideoSectionHeader title={title} showViewAll={false} />
      {/* The inner `Column(stretch, spacing: spacingLarge)` — cards, then the action. */}
      <div className={styles.cards}>
        {videos.map((video) => (
          <VideoCarouselCard key={video.videoId} video={video} size="lg" />
        ))}
        <VideoViewAllAction style="row" />
      </div>
    </section>
  );
}
