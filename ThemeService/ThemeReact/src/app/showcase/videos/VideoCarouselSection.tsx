// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// video_carousel_section.dart — a titled section with a horizontally scrolling
// row of video cards and a "view all" affordance on the right.
//
// Also ports the header half of `level_up_videos/level_up_videos_header.dart`,
// which is the byte-identical `Row(Expanded(Text(h2)), 'view all' underlined)`
// under a different name; the two Dart files differ only in the padding token
// their owner wraps them in, so that arrives as a prop here.
//
// THE ROW SCROLLS AND THE PAGE DOES TOO. Dart nests a horizontal
// `SingleChildScrollView` inside the screen's vertical one; the CSS equivalent
// is `overflow-x: auto` on the row inside the scaffold's opted-in vertical
// scroller (../support/ShowcaseScaffold.tsx). The row's own inline padding is
// what lets the first and last card sit at the screen inset while the cards
// still scroll edge to edge.

import type { ShowcaseVideo } from '../showcaseContent';
import { showcaseStyle } from '../showcaseTokens';

import { VideoCarouselCard } from './VideoCarouselCard';
import styles from './VideoCarouselSection.module.css';

export interface VideoCarouselSectionProps {
  title: string;
  videos: readonly ShowcaseVideo[];
  /**
   * The inline padding the header and the row's ends sit at. The videos tab
   * uses `screenHorizontalPadding` (video_carousel_section.dart:30) and the
   * profile uses `paddingBig` (level_up_videos_section.dart:79) — the one real
   * difference between the two Dart sections.
   */
  inset?: 'screen' | 'big';
}

export function VideoCarouselSection({
  title,
  videos,
  inset = 'screen',
}: VideoCarouselSectionProps) {
  const insetVar = inset === 'big' ? 'var(--sc-padding-big)' : 'var(--sc-screen-padding-x)';
  return (
    // `Column(stretch, spacing: spacingLarge)`.
    <section className={styles.section} style={showcaseStyle({ '--vc-inset': insetVar })}>
      {/* `Padding(horizontal: inset) > _SectionHeader`. */}
      <header className={styles.header}>
        <h2 className={styles.title}>{title}</h2>
        {/*
          `Text('view all', decoration: underline, decorationColor: text)`.
          Preview-only, so it is a label rather than a control — there is no
          route behind it and a dead <button> would advertise an action the
          phone cannot take.
        */}
        <span className={styles.viewAll}>view all</span>
      </header>
      {/* `SingleChildScrollView(horizontal) > Row(spacing: spacingLarge)`. */}
      <div className={styles.row}>
        {videos.map((video) => (
          <VideoCarouselCard key={video.videoId} video={video} />
        ))}
      </div>
    </section>
  );
}
