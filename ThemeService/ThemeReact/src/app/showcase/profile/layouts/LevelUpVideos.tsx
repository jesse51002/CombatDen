// Ports ../../../../../../../MobileApp/lib/features/profile/presentation/
// widgets/level_up_videos/level_up_videos_section.dart — "Videos to level up",
// the Education-bucket cards from the live feed as a horizontal carousel.
//
// IT HIDES ITSELF WHEN EMPTY (Dart's `SizedBox.shrink()`), so a tenant whose
// feed carries no educational videos gets no header over nothing — and THE
// DIVIDER GOES WITH IT. Every Dart layout writes an unconditional
// `SectionDivider()` before the section, which draws a rule under nothing for
// exactly that tenant; the divider is a sibling of the section here so the two
// appear and disappear together. That divergence is deliberate, and it is the
// behaviour this screen already shipped with.
//
// The carousel itself is ../../videos/VideoCarouselSection.tsx, which also
// ports `level_up_videos_header.dart` — the two Dart sections differ only in
// the padding token their owner wraps them in, which arrives as `inset`.

import type { ShowcaseVideo } from '../../showcaseContent';
import { VideoCarouselSection } from '../../videos/VideoCarouselSection';

import { RANK_PART } from '../rankParts';
import { RankPartMarker } from '../rankLayoutData';

import styles from './rankLayouts.module.css';

/**
 * The trailing block every arrangement ends with: the rule, then the carousel.
 * One component so the "no rule over an empty section" rule cannot be got wrong
 * in one of five places.
 */
export function LevelUpVideos({ videos }: { videos: readonly ShowcaseVideo[] }) {
  if (videos.length === 0) return null;
  return (
    <RankPartMarker part={RANK_PART.levelUpVideos}>
      <div className={styles.divider} />
      <VideoCarouselSection title="Videos to level up" videos={videos} inset="big" />
    </RankPartMarker>
  );
}
