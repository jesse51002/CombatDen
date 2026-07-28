// Ports ../../../../../../MobileApp/lib/shared/widgets/video_recc_card/
// creator_avatar.dart — the single place that decides whether a video has a
// creator avatar, and the circle itself.
//
// AN EMPTY URL IS "NO AVATAR", NOT "A BROKEN AVATAR". The shared video pool
// routinely carries no avatar for a channel and the field arrives as `''`
// rather than null, so every call site OMITS the circle instead of rendering a
// broken one — which is also why the row's `gap` is the only thing left behind
// (no placeholder, no reserved space).
//
// A URL THAT FAILS COLLAPSES THE SAME WAY. YouTube rotates a channel's avatar
// URL whenever the creator changes their picture, so a stored URL goes stale
// and 404s on its own; a stale avatar drawn as a filled disc is worse than no
// avatar at all. Dart spells this `errorBuilder: SizedBox.shrink()`; here the
// <img> is removed on error and the `key` remount resets that decision whenever
// the URL changes (the same idiom ../home/ClassListItem.tsx uses — resetting in
// an effect is a lint error in this package, see ../../../CLAUDE.md).

import { useState } from 'react';

import styles from './CreatorAvatar.module.css';

/** Ports `creatorAvatarProvider` — a blank/whitespace URL means no avatar. */
export function hasCreatorAvatar(url: string | null | undefined): boolean {
  return (url ?? '').trim() !== '';
}

export interface CreatorAvatarProps {
  url: string;
  /** Edge length in px. An asset dimension, not a spacing token — see the Dart. */
  size: number;
}

export function CreatorAvatar({ url, size }: CreatorAvatarProps) {
  if (!hasCreatorAvatar(url)) return null;
  return <AvatarImage key={url} url={url.trim()} size={size} />;
}

function AvatarImage({ url, size }: CreatorAvatarProps) {
  const [failed, setFailed] = useState(false);
  if (failed) return null;
  return (
    <img
      className={styles.avatar}
      src={url}
      alt=""
      style={{ width: `${String(size)}px`, height: `${String(size)}px` }}
      onError={() => {
        setFailed(true);
      }}
    />
  );
}
