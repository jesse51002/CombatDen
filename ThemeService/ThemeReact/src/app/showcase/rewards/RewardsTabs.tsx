// Ports ../../../../../../MobileApp/lib/features/rewards/presentation/widgets/
// rewards_tabs/{rewards_tabs,rewards_tabs_underline,rewards_tabs_segmented}.dart
// — the two-tab selector both rewards screens carry, in its two chromes.
//
// `underline` ships: the active tab takes the accent tint and an underline, the
// inactive one is dim and has none. `segmented` puts both tabs inside one pill
// and fills the active one. PRESENTATION ONLY — both render the same two
// labelled targets with the same one active, which is why a screen arrangement
// may pick either without touching the invariant.
//
// NO TAP CALLBACKS. Dart's widget accepts `onPointsStoreTap` / `onMyRewardsTap`
// and the store passes neither, because every showcase surface is a preview
// inside a phone frame that takes no input. The port drops them rather than
// carrying two props nothing can ever pass — the same call
// ../support/ShowcaseBottomNav.tsx makes for its own nav items.

import { cx } from '../cx';

import styles from './RewardsTabs.module.css';

/** `RewardsTab` — which tab is currently selected. */
export type RewardsTab = 'pointsStore' | 'myRewards';

/** `RewardsTabsLayout` — how the strip is drawn. */
export type RewardsTabsLayout = 'underline' | 'segmented';

export interface RewardsTabsProps {
  active: RewardsTab;
  layout?: RewardsTabsLayout | undefined;
}

export function RewardsTabs({ active, layout = 'underline' }: RewardsTabsProps) {
  if (layout === 'segmented') {
    return (
      // `Padding(horizontal: screenHorizontalPadding) > Container(padding:
      // spacingSmall, color: card, borderRadius: radiusCircle) > Row(spacingSmall)`.
      <div className={styles.segmentedOuter}>
        <div className={styles.segmented}>
          <Segment label="Points Store" isActive={active === 'pointsStore'} />
          <Segment label="My Rewards" isActive={active === 'myRewards'} />
        </div>
      </div>
    );
  }
  return (
    // `Container(border: Border(bottom: text3rd @ dividerThickness), padding: …)`.
    <div className={styles.tabs}>
      <TabItem label="Points Store" isActive={active === 'pointsStore'} />
      <TabItem label="My Rewards" isActive={active === 'myRewards'} />
    </div>
  );
}

/**
 * `_TabItem` — an `Expanded` cell whose own bottom border is the underline.
 * Inactive draws that border in the CANVAS colour rather than omitting it, so
 * the two tabs keep identical heights; the port keeps that (`transparent` would
 * work too, but the Dart's choice is what a reviewer sees when the canvas and
 * the card differ).
 */
function TabItem({ label, isActive }: { label: string; isActive: boolean }) {
  return (
    <span className={cx(styles.tab, isActive && styles.active)}>
      <span className={styles.label}>{label}</span>
    </span>
  );
}

/** `_Segment` — an `Expanded` pill; the active one takes the accent fill. */
function Segment({ label, isActive }: { label: string; isActive: boolean }) {
  return (
    <span className={cx(styles.segment, isActive && styles.segmentActive)}>
      <span className={styles.segmentLabel}>{label}</span>
    </span>
  );
}
