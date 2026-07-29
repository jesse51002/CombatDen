// Ports ../../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// sections/video_section_header.dart — a genre section's title, with the "view
// all" action when the section carries it inline.
//
// Also ports the header half of `level_up_videos/level_up_videos_header.dart`,
// which is the byte-identical `Row(Expanded(Text(h2)), 'view all' underlined)`
// under a different name; the two Dart files differ only in the padding token
// their owner wraps them in, so that arrives here as the `--vc-inset` variable
// the placing section sets.
//
// THE ACTION NEVER DISAPPEARS — IT MOVES. `showViewAll: false` is what a
// section passes when it renders the action somewhere else (a row beneath the
// cards, a tile in the grid); it is never a section dropping the affordance.
// That distinction is exactly what ../__tests__/videosFormats.test.tsx
// counts.

import { cx } from '../../cx';
import { PART_ATTR, VIDEO_PARTS } from '../videoParts';
import { VideoViewAllAction } from '../VideoViewAllAction';

import styles from './VideoSectionHeader.module.css';

/** `VideoSectionHeaderStyle` — how the title is drawn. */
export type VideoSectionHeaderStyle = 'plain' | 'divider' | 'overlay';

export interface VideoSectionHeaderProps {
  title: string;
  /**
   * False when the section places the action elsewhere. The action itself never
   * disappears — see the header.
   */
  showViewAll?: boolean | undefined;
  style?: VideoSectionHeaderStyle | undefined;
}

export function VideoSectionHeader({
  title,
  showViewAll = true,
  style = 'plain',
}: VideoSectionHeaderProps) {
  // `Row(crossAxisAlignment: center)`. The divider variant adds a hairline that
  // eats the slack instead of the title, so the title sizes to its text there.
  const row = (
    <header className={cx(styles.header, style === 'divider' && styles.divider)}>
      <h2 className={styles.title} {...{ [PART_ATTR]: VIDEO_PARTS.sectionTitle }}>
        {title}
      </h2>
      {/* `Expanded(child: Container(height: dividerThickness, color: divider))`. */}
      {style === 'divider' && <span className={styles.rule} />}
      {showViewAll && <VideoViewAllAction />}
    </header>
  );

  if (style !== 'overlay') return row;
  // `ColoredBox(popup) > Padding(horizontal: paddingSmall, vertical: spacingMedium)`.
  return <div className={styles.band}>{row}</div>;
}
