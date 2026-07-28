// No single Dart counterpart — this is the `Image(… errorBuilder: (_, _, _) =>
// ColoredBox(color: card))` that `video_recc_card.dart:47-52` and
// `gym_video_carousel_card.dart:41-46` each spell inline, lifted once.
//
// A YouTube thumbnail is a stored URL that can rotate or 404 on its own, so a
// dead one must degrade to the flat `card` rectangle the box already paints
// rather than to a broken-image glyph. The `key` remount is what resets that
// decision when the URL changes — a category switch swaps the whole feed, and
// without it one dead URL would pin its slot to the empty box forever (the same
// idiom ../home/classItem/ClassItemThumb.tsx and ../rewards/RewardCard.tsx use; resetting
// in an effect is a lint error in this package, see ../../../CLAUDE.md).

import { useState } from 'react';

import { PART_ATTR, VIDEO_PARTS } from './videoParts';
import styles from './VideoThumbnail.module.css';

export interface VideoThumbnailProps {
  src: string;
  /** Extra class from the owning card — it sizes the box, this fills it. */
  className?: string | undefined;
}

export function VideoThumbnail({ src, className }: VideoThumbnailProps) {
  return <ThumbnailImage key={src} src={src} className={className} />;
}

function ThumbnailImage({ src, className }: VideoThumbnailProps) {
  const [failed, setFailed] = useState(false);
  if (failed || src === '') return null;
  return (
    <img
      className={className === undefined ? styles.thumb : `${styles.thumb} ${className}`}
      src={src}
      alt=""
      loading="lazy"
      decoding="async"
      onError={() => {
        setFailed(true);
      }}
      {...{ [PART_ATTR]: VIDEO_PARTS.thumb }}
    />
  );
}
