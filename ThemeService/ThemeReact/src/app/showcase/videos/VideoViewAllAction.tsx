// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// video_view_all_action.dart — a section's "view all" affordance: ONE action,
// three treatments.
//
// The three exist so an arrangement can MOVE the action rather than drop it.
// `link` sits inline in the header (shipped), `row` closes a stacked section
// beneath its cards, `tile` takes the last cell of a mosaic. Which one a
// section uses is the section's call; that it is present is not.
//
// Preview-only, so it is a label rather than a control — there is no route
// behind it and a dead <button> would advertise an action the phone cannot
// take, exactly as ../rewards/RewardsTabs.tsx concluded for its own tabs.

import { cx } from '../cx';

import { PART_ATTR, VIDEO_PARTS } from './videoParts';
import styles from './VideoViewAllAction.module.css';

/** `VideoViewAllStyle` — how the affordance is drawn. Presentation only. */
export type VideoViewAllStyle = 'link' | 'row' | 'tile';

/** `_kLabel`. */
const LABEL = 'view all';

export interface VideoViewAllActionProps {
  style?: VideoViewAllStyle | undefined;
}

export function VideoViewAllAction({ style = 'link' }: VideoViewAllActionProps) {
  // `_Label` — `Text('view all', decoration: underline, decorationColor: text)`.
  if (style === 'link') {
    return (
      <span className={styles.viewAll} {...{ [PART_ATTR]: VIDEO_PARTS.viewAll }}>
        {LABEL}
      </span>
    );
  }

  // `_Surface(child: Center(child: _Label()))`.
  return (
    <div
      className={cx(styles.surface, style === 'tile' ? styles.tile : styles.rowSurface)}
      {...{ [PART_ATTR]: VIDEO_PARTS.viewAll }}
    >
      <span className={styles.viewAll}>{LABEL}</span>
    </div>
  );
}
