// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// featured_video_card.dart — the big hero at the top of the videos tab: a
// ./VideoReccCard.tsx wrapped in a card surface with a full-width, fully
// rounded "Play" CTA underneath.
//
// The CTA's `borderRadius: 100` is the Dart's own literal rather than a token,
// and it reads as a pill at any button height — so it ports as the island's
// `radiusCircle` (1000), which is the same intent expressed in the token
// system rather than a second magic number at the call site.
//
// `FeaturedVideoLayout` IS HOW THE HERO MEETS THE SCREEN EDGE, and it is the
// only thing an arrangement gets to change about it: `card` sits inside the
// gutter with rounded corners (shipped), `bleed` squares off and runs edge to
// edge so the hero reads as a poster the page starts with. The caller drops its
// own horizontal inset to match.

import type { ShowcaseVideo } from '../showcaseContent';
import { cx } from '../cx';
import { ShowcasePrimaryButton } from '../support/ShowcasePrimaryButton';

import styles from './FeaturedVideoCard.module.css';
import { PART_ATTR, VIDEO_PARTS } from './videoParts';
import { VideoReccCard } from './VideoReccCard';

/** `FeaturedVideoLayout` — how the hero meets the screen edge. */
export type FeaturedVideoLayout = 'card' | 'bleed';

export interface FeaturedVideoCardProps {
  video: ShowcaseVideo;
  layout?: FeaturedVideoLayout | undefined;
}

export function FeaturedVideoCard({ video, layout = 'card' }: FeaturedVideoCardProps) {
  return (
    // `Container(color: card, radiusBig, clipBehavior: hardEdge) >
    // Column(stretch, spacing: spacingLarge)`.
    <div
      className={cx(styles.card, layout === 'bleed' && styles.bleed)}
      {...{ [PART_ATTR]: VIDEO_PARTS.featured }}
    >
      <VideoReccCard video={video} />
      {/* `Padding(paddingBig, 0, paddingBig, spacingLarge)`. */}
      <div className={styles.ctaRow} {...{ [PART_ATTR]: VIDEO_PARTS.featuredPlay }}>
        <ShowcasePrimaryButton text="Play" fullWidth borderRadius="var(--sc-radius-circle)" />
      </div>
    </div>
  );
}
