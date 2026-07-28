// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// gym_video_carousel_card.dart, plus the `VideoCardSize` shapes that
// video_carousel_card.dart declares — the card every genre section is built
// from, in the four shapes the layout arrangements need.
//
// ONE CARD HERE, TWO THERE. `video_carousel_card.dart` and
// `gym_video_carousel_card.dart` are the same layout over two models — the
// retired `Video` and the portal's `GymVideoCard` — and Dart keeps both because
// each still has a consumer. This island has one model, so it gets one card
// (../../../CLAUDE.md: never reproduce an existing duplication to stay
// "consistent" with the code being ported). `VideoCardSize` lives on the first
// of the two; the shapes it names are the same either way.
//
// A SIZE IS PRESENTATION ONLY, which is what lets an arrangement pick one:
// every value renders the same thumbnail, title, channel avatar and view count.
// Only `tall` changes the composition, and it changes where the meta line SITS,
// not what it says.
//
// Also the Profile screen's carousel card: `level_up_videos_section.dart:99`
// renders this same widget at the default size, which is why it lives here
// rather than under the Video screen's own folder.

import type { ShowcaseVideo } from '../showcaseContent';
import { cx } from '../cx';

import { VideoCardInfo } from './VideoCardInfo';
import styles from './VideoCarouselCard.module.css';
import { PART_ATTR, VIDEO_PARTS } from './videoParts';
import { VideoThumbnail } from './VideoThumbnail';

/**
 * `VideoCardSize` — how a card is shaped.
 *
 * - `md` — 258 wide with a fixed 145 thumbnail; the card the horizontal rows
 *   ship today, and this component's default exactly as it is Dart's.
 * - `lg` — fills its column at 16:9.
 * - `tile` — fills its grid cell at 16:9 with a denser meta line.
 * - `tall` — the meta line rides a caption band over the image.
 */
export type VideoCardSize = 'md' | 'lg' | 'tile' | 'tall';

export interface VideoCarouselCardProps {
  video: ShowcaseVideo;
  size?: VideoCardSize | undefined;
}

export function VideoCarouselCard({ video, size = 'md' }: VideoCarouselCardProps) {
  // `_Captioned` — the artwork stays 16:9 and the CARD grows a band over it.
  if (size === 'tall') {
    return (
      <article
        className={cx(styles.card, styles.fill, styles.tall)}
        {...{ [PART_ATTR]: VIDEO_PARTS.card }}
      >
        <div className={cx(styles.thumbFrame, styles.thumbRatio)}>
          <VideoThumbnail src={video.thumbnailUrl} />
        </div>
        {/* `Positioned(bottom) > ColoredBox(popup) > Padding(spacingMedium)`. */}
        <div className={styles.caption}>
          <VideoCardInfo video={video} compact flush />
        </div>
      </article>
    );
  }

  return (
    // `SizedBox(width: 258) > Container(color: card, radiusSmall, clip: hardEdge)`.
    <article
      className={cx(styles.card, size !== 'md' && styles.fill)}
      {...{ [PART_ATTR]: VIDEO_PARTS.card }}
    >
      <div className={cx(styles.thumbFrame, size !== 'md' && styles.thumbRatio)}>
        <VideoThumbnail src={video.thumbnailUrl} />
      </div>
      <VideoCardInfo video={video} compact={size === 'tile'} />
    </article>
  );
}
