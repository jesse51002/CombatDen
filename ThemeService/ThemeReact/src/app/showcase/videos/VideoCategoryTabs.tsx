// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// video_category_tabs.dart — the top-filter pills for the videos tab ("All"
// plus one per genre in the feed), on either axis.
//
// IT SCROLLS IN THE REAL APP TOO, and for the same reason: the genre set is
// open-ended (up to nine values), so a fixed centred row would overflow. The
// Dart centres the row inside its scroller so a short set sits centred and a
// long one starts at the inset; `justify-content: center` on an
// `overflow-x: auto` flex row does exactly that, except that a centred
// overflowing row clips its own leading edge in CSS — which is what the
// `margin-inline: auto` on the inner row avoids.
//
// THE AXIS IS THE FILTER'S ONE DEGREE OF FREEDOM. `tagRail` moves the filter
// off the top and into a rail down the left; it is the same pills, the same
// selection and the same open-ended set, running down instead of across. An
// arrangement may move the filter — it may not reword it, shorten it, or drop
// it.
//
// TAPS ARE NO-OPS. In the app a genre pill OPENS that genre's full list
// (`TagVideosScreen`) rather than filtering this screen; there is no navigator
// in a phone mock, so the pills are labels and "All" is always the active one.
// A dead <button> would advertise an action the preview cannot take, exactly as
// ../rewards/RewardsTabs.tsx concluded for its own two tabs.

import { cx } from '../cx';

import { PART_ATTR, VIDEO_PARTS } from './videoParts';
import styles from './VideoCategoryTabs.module.css';

/** `VideoCategoryTabsAxis` — how the pills are laid out. */
export type VideoCategoryTabsAxis = 'horizontal' | 'vertical';

export interface VideoCategoryTabsProps {
  /** `['All', ...genres.map((g) => g.label)]` — already labelled. */
  tabs: readonly string[];
  selectedIndex: number;
  axis?: VideoCategoryTabsAxis | undefined;
}

export function VideoCategoryTabs({
  tabs,
  selectedIndex,
  axis = 'horizontal',
}: VideoCategoryTabsProps) {
  const vertical = axis === 'vertical';
  return (
    // `Padding(vertical: spacingLarge) > SingleChildScrollView(axis)`.
    <div
      className={cx(styles.strip, vertical && styles.stripVertical)}
      {...{ [PART_ATTR]: VIDEO_PARTS.categoryTabs }}
    >
      <div className={cx(styles.row, vertical && styles.column)}>
        {tabs.map((label, index) => (
          <span
            // Genre labels are distinct by construction (`genresInFeed` dedups),
            // so the label IS the pill's identity.
            key={label}
            className={cx(styles.pill, index === selectedIndex && styles.active)}
            {...{ [PART_ATTR]: VIDEO_PARTS.categoryPill }}
          >
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
