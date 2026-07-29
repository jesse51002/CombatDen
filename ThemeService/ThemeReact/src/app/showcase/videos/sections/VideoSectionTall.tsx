// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// sections/video_section_tall.dart — a genre section as one column of poster
// cards, its title riding the top of the FIRST card instead of standing above
// the section.
//
// The section reads as a run of full-height posters, which is the shape members
// already know from the platforms this content comes from. Because the title
// sits on artwork, its header takes the opaque `overlay` treatment and keeps
// its "view all" inline — the action does not move here, only the title does.
//
// An empty section is the header alone: Dart returns it early rather than
// building a stack around a card that does not exist.

import type { ShowcaseVideo } from '../../showcaseContent';
import { PART_ATTR, VIDEO_PARTS } from '../videoParts';
import { VideoCarouselCard } from '../VideoCarouselCard';

import { VideoSectionHeader } from './VideoSectionHeader';
import styles from './VideoSectionTall.module.css';

export interface VideoSectionTallProps {
  title: string;
  videos: readonly ShowcaseVideo[];
}

export function VideoSectionTall({ title, videos }: VideoSectionTallProps) {
  const header = <VideoSectionHeader title={title} style="overlay" />;
  const [first, ...rest] = videos;

  if (first === undefined) {
    return (
      <section className={styles.section} {...{ [PART_ATTR]: VIDEO_PARTS.section }}>
        {header}
      </section>
    );
  }

  return (
    // `Column(stretch, spacing: spacingLarge)`.
    <section className={styles.section} {...{ [PART_ATTR]: VIDEO_PARTS.section }}>
      {/* `ClipRRect(radiusSmall) > Stack[card, Positioned(l, r, t: 0) header]`. */}
      <div className={styles.first}>
        <VideoCarouselCard video={first} size="tall" />
        <div className={styles.overlay}>{header}</div>
      </div>
      {rest.map((video) => (
        <VideoCarouselCard key={video.videoId} video={video} size="tall" />
      ))}
    </section>
  );
}
