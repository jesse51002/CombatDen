// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// gym_video_carousel_card.dart — the compact card inside a horizontally
// scrolling genre carousel: a fixed 258x145 thumbnail over the avatar, title
// and view count.
//
// ONE CARD HERE, TWO THERE. `video_carousel_card.dart` and
// `gym_video_carousel_card.dart` are the same layout over two models — the
// retired `Video` and the portal's `GymVideoCard` — and Dart keeps both because
// each still has a consumer. This island has one model, so it gets one card
// (../../../CLAUDE.md: never reproduce an existing duplication to stay
// "consistent" with the code being ported).
//
// Also the Profile screen's carousel card: `level_up_videos_section.dart:99`
// renders this same widget, which is why it lives here rather than under the
// Video screen's own folder.

import type { ShowcaseVideo } from '../showcaseContent';

import { CreatorAvatar } from './CreatorAvatar';
import styles from './VideoCarouselCard.module.css';
import { formatViewCount } from './videoSelectors';
import { VideoThumbnail } from './VideoThumbnail';

/** `_kPfpSize` — an asset dimension, not a spacing token. */
const PFP_SIZE = 35;

export interface VideoCarouselCardProps {
  video: ShowcaseVideo;
}

export function VideoCarouselCard({ video }: VideoCarouselCardProps) {
  const views = formatViewCount(video.viewCount);
  return (
    // `SizedBox(width: 258) > Container(color: card, radiusSmall, clip: hardEdge)`.
    <article className={styles.card}>
      <div className={styles.thumbFrame}>
        <VideoThumbnail src={video.thumbnailUrl} />
      </div>
      {/* `Padding(spacingMedium, 0, spacingMedium, spacingLarge) > _Info`. */}
      <div className={styles.info}>
        <CreatorAvatar url={video.channelAvatarUrl} size={PFP_SIZE} />
        <div className={styles.text}>
          <span className={styles.title}>{video.title}</span>
          {/* `views.isEmpty ? channelName : '$views views'` — verbatim. */}
          <span className={styles.meta}>
            {views === '' ? video.channelName : `${views} views`}
          </span>
        </div>
      </div>
    </article>
  );
}
