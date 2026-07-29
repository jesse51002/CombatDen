// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// cards/video_card_info.dart — channel avatar + title + view count, the meta
// line every video card carries whatever shape the card takes.
//
// Lifted out of ./VideoCarouselCard.tsx when that card grew the four
// `VideoCardSize` shapes, for the Dart file's own reason: the caption band on a
// tall card and the tiles in a mosaic render the identical line at a smaller
// avatar, and a second copy would be a second thing to keep in step.

import type { ShowcaseVideo } from '../showcaseContent';
import { cx } from '../cx';

import { CreatorAvatar } from './CreatorAvatar';
import styles from './VideoCardInfo.module.css';
import { formatViewCount } from './videoSelectors';

/** `_kPfpSize` / `_kPfpSizeCompact` — asset dimensions, not spacing tokens. */
const PFP_SIZE = 35;
const PFP_SIZE_COMPACT = 28;

export interface VideoCardInfoProps {
  video: ShowcaseVideo;
  /**
   * Shrinks the avatar for the denser card shapes (grid tiles, the caption band
   * on a tall card). Text styles are unchanged — the Dart's own comment.
   */
  compact?: boolean | undefined;
  /**
   * Drops the card-surface inset this line normally holds itself at, for the
   * one consumer that supplies its own: the tall card's caption band, which
   * pads the whole band rather than the row inside it (`_Captioned`).
   */
  flush?: boolean | undefined;
}

export function VideoCardInfo({ video, compact = false, flush = false }: VideoCardInfoProps) {
  const views = formatViewCount(video.viewCount);
  return (
    // `Padding(spacingMedium, 0, spacingMedium, spacingLarge) >
    // Row(center, spacing: spacingMedium)`.
    <div className={cx(styles.info, flush && styles.flush)}>
      <CreatorAvatar url={video.channelAvatarUrl} size={compact ? PFP_SIZE_COMPACT : PFP_SIZE} />
      <div className={styles.text}>
        <span className={styles.title}>{video.title}</span>
        {/* `views.isEmpty ? channelName : '$views views'` — verbatim. */}
        <span className={styles.meta}>{views === '' ? video.channelName : `${views} views`}</span>
      </div>
    </div>
  );
}
