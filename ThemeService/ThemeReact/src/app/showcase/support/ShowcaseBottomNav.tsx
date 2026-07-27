// Ports ../../../../../../CRM/lib/showcase/support/showcase_bottom_nav.dart —
// a clone of MobileApp's `AppBottomNavBar` + `AppNavItem`. Preview-only: taps
// are no-ops, there is no routing.
//
// The four glyphs are BRAND-OVERRIDABLE: each resolves the theme's matching
// `nav_*` icon slot through the library's <ThemeIcon>, which masks the tenant
// SVG with the tint colour (Dart's `ColorFilter.mode(tint, BlendMode.srcIn)`)
// and keeps the bundled glyph on screen until the override's URL has actually
// probed — a 404'd CSS mask renders an EMPTY BOX rather than failing loudly.

import type { ReactElement } from 'react';
import { ThemeIcon } from 'theme-react';

import {
  SLOT_NAV_HOME,
  SLOT_NAV_RANK,
  SLOT_NAV_REWARD,
  SLOT_NAV_VIDEOS,
} from '../showcaseSlots';
import { SC } from '../showcaseTokens';

import { HomeIcon, RankIcon, RewardIcon, VideosIcon } from './icons';
import styles from './ShowcaseBottomNav.module.css';

/** `ShowcaseNavTab`, in `values` order. */
export type ShowcaseNavTab = 'home' | 'rank' | 'reward' | 'videos';

interface NavSpec {
  readonly tab: ShowcaseNavTab;
  readonly slot: string;
  readonly label: string;
  readonly Icon: (props: { size?: number | undefined }) => ReactElement;
}

const TABS: readonly NavSpec[] = Object.freeze([
  { tab: 'home', slot: SLOT_NAV_HOME, label: 'Home', Icon: HomeIcon },
  { tab: 'rank', slot: SLOT_NAV_RANK, label: 'Rank', Icon: RankIcon },
  { tab: 'reward', slot: SLOT_NAV_REWARD, label: 'Reward', Icon: RewardIcon },
  { tab: 'videos', slot: SLOT_NAV_VIDEOS, label: 'Videos', Icon: VideosIcon },
]);

/** `_kBottomNavRowHeight` — a local const in Dart too, not a design token. */
const ROW_HEIGHT = 64;

/** `ShowcaseTokens.iconSizeMd`. Passed to <ThemeIcon>, which sizes in px. */
const ICON_SIZE = SC.iconSizeMd;

export interface ShowcaseBottomNavProps {
  selected: ShowcaseNavTab;
}

export function ShowcaseBottomNav({ selected }: ShowcaseBottomNavProps) {
  return (
    // Dart adds `MediaQuery.padding.bottom` here; the phone frame publishes no
    // bottom inset (its `MediaQuery` override is `EdgeInsets.only(top:)`), so
    // there is nothing to add.
    <nav className={styles.nav} style={{ height: `${String(ROW_HEIGHT)}px` }}>
      {TABS.map(({ tab, slot, label, Icon }) => (
        <NavItem
          key={tab}
          slot={slot}
          label={label}
          icon={<Icon />}
          isActive={tab === selected}
        />
      ))}
    </nav>
  );
}

interface NavItemProps {
  slot: string;
  label: string;
  icon: ReactElement;
  isActive: boolean;
}

function NavItem({ slot, label, icon, isActive }: NavItemProps) {
  // `isActive ? accent : text2nd` — accent is the member app's selection /
  // active-state role, exactly as in `AppNavItem`. It is the ONLY active-state
  // affordance the Dart widget has, so there is no second class to toggle.
  const color = isActive ? 'var(--sc-accent)' : 'var(--sc-text-2nd)';
  return (
    <div className={styles.item} style={{ color }}>
      <ThemeIcon slot={slot} fallback={icon} color={color} size={ICON_SIZE} />
      <span className={styles.label}>{label}</span>
    </div>
  );
}
