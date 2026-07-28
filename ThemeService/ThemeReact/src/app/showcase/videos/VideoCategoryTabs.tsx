// Ports ../../../../../../MobileApp/lib/features/videos/presentation/widgets/
// video_category_tabs.dart — the pill row across the top of the videos tab
// ("All" plus one per genre in the feed).
//
// IT SCROLLS HORIZONTALLY IN THE REAL APP TOO, and for the same reason: the
// genre set is open-ended (up to nine values), so a fixed centred row would
// overflow. The Dart centres the row inside its scroller so a short set sits
// centred and a long one starts at the inset; `justify-content: center` on an
// `overflow-x: auto` flex row does exactly that, except that a centred
// overflowing row clips its own leading edge in CSS — which is what the
// `margin-inline: auto` on the inner row avoids.
//
// TAPS ARE NO-OPS. In the app a genre pill OPENS that genre's full list
// (`TagVideosScreen`) rather than filtering this screen; there is no navigator
// in a phone mock, so the pills are labels and "All" is always the active one.
// A dead <button> would advertise an action the preview cannot take, exactly as
// ../rewards/RewardsTabs.tsx concluded for its own two tabs.

import { cx } from '../cx';

import styles from './VideoCategoryTabs.module.css';

export interface VideoCategoryTabsProps {
  /** `['All', ...genres.map((g) => g.label)]` — already labelled. */
  tabs: readonly string[];
  selectedIndex: number;
}

export function VideoCategoryTabs({ tabs, selectedIndex }: VideoCategoryTabsProps) {
  return (
    // `Padding(vertical: spacingLarge) > SingleChildScrollView(horizontal)`.
    <div className={styles.strip}>
      <div className={styles.row}>
        {tabs.map((label, index) => (
          <span
            // Genre labels are distinct by construction (`genresInFeed` dedups),
            // so the label IS the pill's identity.
            key={label}
            className={cx(styles.pill, index === selectedIndex && styles.active)}
          >
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
