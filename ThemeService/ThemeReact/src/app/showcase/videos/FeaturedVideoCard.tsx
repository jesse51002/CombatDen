// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// featured_video_card.dart — the big hero at the top of the videos tab: a
// ./VideoReccCard.tsx wrapped in a card surface with a full-width, fully
// rounded "Play" CTA underneath.
//
// The CTA's `borderRadius: 100` is the Dart's own literal rather than a token,
// and it reads as a pill at any button height — so it ports as the island's
// `radiusCircle` (1000), which is the same intent expressed in the token
// system rather than a second magic number at the call site.

import type { ShowcaseVideo } from '../showcaseContent';
import { ShowcasePrimaryButton } from '../support/ShowcasePrimaryButton';

import styles from './FeaturedVideoCard.module.css';
import { VideoReccCard } from './VideoReccCard';

export interface FeaturedVideoCardProps {
  video: ShowcaseVideo;
}

export function FeaturedVideoCard({ video }: FeaturedVideoCardProps) {
  return (
    // `Container(color: card, radiusBig, clipBehavior: hardEdge) >
    // Column(stretch, spacing: spacingLarge)`.
    <div className={styles.card}>
      <VideoReccCard video={video} />
      {/* `Padding(paddingBig, 0, paddingBig, spacingLarge)`. */}
      <div className={styles.ctaRow}>
        <ShowcasePrimaryButton text="Play" fullWidth borderRadius="var(--sc-radius-circle)" />
      </div>
    </div>
  );
}
