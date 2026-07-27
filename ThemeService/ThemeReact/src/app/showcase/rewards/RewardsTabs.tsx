// Ports ../../../../../../CRM/lib/showcase/rewards/rewards_tabs.dart — a clone
// of MobileApp's two-tab segmented selector: the active tab takes the accent
// tint and an underline, the inactive one is dim and has none.
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

export interface RewardsTabsProps {
  active: RewardsTab;
}

export function RewardsTabs({ active }: RewardsTabsProps) {
  return (
    // `Container(border: Border(bottom: text3rd @ dividerThickness), padding: …)`.
    <div className={styles.tabs}>
      <TabItem label="Points Store" isActive={active === 'pointsStore'} />
      <TabItem label="My Rewards" isActive={active === 'myRewards'} />
    </div>
  );
}

/**
 * `_RewardsTabItem` — an `Expanded` cell whose own bottom border is the
 * underline. Inactive draws that border in the CANVAS colour rather than
 * omitting it, so the two tabs keep identical heights; the port keeps that
 * (`transparent` would work too, but the Dart's choice is what a reviewer sees
 * when the canvas and the card differ).
 */
function TabItem({ label, isActive }: { label: string; isActive: boolean }) {
  return (
    <span className={cx(styles.tab, isActive && styles.active)}>
      <span className={styles.label}>{label}</span>
    </span>
  );
}
