// Ports ../../../../../../MobileApp/lib/shared/widgets/video_recc_card/
// video_recc_card.dart — the full-width video recommendation card: a
// square-cornered 16:9 thumbnail over a row of the creator's avatar, the title
// and a meta line.
//
// `roundThumbnail` is NOT ported. Dart carries it because the recommendation
// surfaces frame the thumbnail with enough inset to round it; the only consumer
// in this island is ./FeaturedVideoCard.tsx, which takes the `false` branch —
// a YouTube thumbnail carries burnt-in text right to its edges, so a `radiusBig`
// corner on a full-width image clips that text, and the featured card's own
// surface rounds the top anyway. An always-false prop would be a lie about what
// the port does (../../../CLAUDE.md).
//
// Nothing here is tappable: every showcase surface is a preview inside a phone
// frame that takes no input, so Dart's `onTap` goes the way
// ../rewards/RewardsTabs.tsx's callbacks did.

import type { ShowcaseVideo } from '../showcaseContent';

import { CreatorAvatar } from './CreatorAvatar';
import styles from './VideoReccCard.module.css';
import { videoMetaLabel } from './videoSelectors';
import { VideoThumbnail } from './VideoThumbnail';

/** `_CreatorRow._kPfpSize` — an asset dimension, not a spacing token. */
const PFP_SIZE = 55;

export interface VideoReccCardProps {
  video: ShowcaseVideo;
}

export function VideoReccCard({ video }: VideoReccCardProps) {
  return (
    // `Column(mainAxisSize: min, stretch, spacing: spacingLarge)`.
    <div className={styles.card}>
      {/* `AspectRatio(16 / 9)` over the cover image. */}
      <div className={styles.thumbFrame}>
        <VideoThumbnail src={video.thumbnailUrl} />
      </div>
      {/*
        `Padding(horizontal: paddingSmall) > Row(center, spacing: spacingMedium)`.
        With no avatar the text is the row's only child, so the gap contributes
        nothing and the title starts flush at the inset.
      */}
      <div className={styles.creatorRow}>
        <CreatorAvatar url={video.channelAvatarUrl} size={PFP_SIZE} />
        <div className={styles.creatorText}>
          <span className={styles.title}>{video.title}</span>
          <span className={styles.meta}>{videoMetaLabel(video)}</span>
        </div>
      </div>
    </div>
  );
}
