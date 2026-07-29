// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// videos_feed_status.dart — the feed's non-content state.
//
// ONE KIND IS REACHABLE HERE, AND THAT IS THE PORT. Dart carries four
// (`loading` / `error` / `empty` / `scopeEmpty`) because its screen awaits a
// portal fetch. This preview resolves its feed synchronously from bundled
// constants (../useShowcaseContent.ts), so the two request states have no
// reachable input — an unreachable spinner is a lie about what the phone does
// — and `empty` / `scopeEmpty` collapse into the one message a host with a
// real, video-less gym would see. The wording is Dart's `scopeEmpty` verbatim.
//
// It is extracted rather than inlined for Dart's own reason: every arrangement
// shows the IDENTICAL state. An arrangement arranges videos; it does not get to
// reword or drop the reason there are none.

import { PART_ATTR, VIDEO_PARTS } from './videoParts';
import styles from './VideosFeedStatus.module.css';

/** `VideosFeedStatusKind.scopeEmpty`'s message. */
const MESSAGE = 'Nothing here yet.';

export function VideosFeedStatus() {
  return (
    <p className={styles.empty} {...{ [PART_ATTR]: VIDEO_PARTS.feedStatus }}>
      {MESSAGE}
    </p>
  );
}
