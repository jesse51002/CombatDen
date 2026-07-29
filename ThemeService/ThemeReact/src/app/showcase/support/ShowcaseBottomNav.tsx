// Ports ../../../../../../CRM/lib/showcase/support/showcase_bottom_nav.dart —
// a clone of MobileApp's `AppBottomNavBar` + `AppNavItem`. Preview-only: taps
// are no-ops, there is no routing.
//
// The four glyphs are BRAND-OVERRIDABLE: each resolves the theme's matching
// `nav_*` icon slot through the library's <ThemeIcon>, which masks the tenant
// SVG with the tint colour (Dart's `ColorFilter.mode(tint, BlendMode.srcIn)`)
// and keeps the bundled glyph on screen until the override's URL has actually
// probed — a 404'd CSS mask renders an EMPTY BOX rather than failing loudly.
//
// THE SHELL ARRANGEMENT (`app_shell_format`). Also ports
// ../../../../../../MobileApp/lib/shared/widgets/nav/app_bottom_nav_bar.dart's
// format switch and its two layouts, `layouts/nav_four_up.dart` and
// `layouts/nav_floating_pill.dart`. Tab ORDER and the destination set are fixed
// across every arrangement — that is muscle memory, not composition — and all
// four are always present; the tenant's slot chooses only how the bar is drawn.
//
// Both layouts render the SAME <NavItem>, which is what keeps the four `nav_*`
// slots resolving through <ThemeIcon> identically in the pill: the pill changes
// the container and whether the label is laid out, never how an icon is found.
// Under `markOnly` the labels are still built and still announced (Dart's
// `Semantics(label: label, child: SizedBox.shrink())`), so an icon-only nav
// keeps every accessible name.

import type { ReactElement } from 'react';
import { ThemeIcon } from 'theme-react';

import { cx } from '../cx';
import type { AppShellFormat } from '../formats';
import { APP_SHELL_FORMATS, FORMAT_SLOTS, useFormat } from '../formats';
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

/** `_kPillHeight` — likewise a local const in `nav_floating_pill.dart`. */
const PILL_HEIGHT = 56;

/** `ShowcaseTokens.iconSizeMd`. Passed to <ThemeIcon>, which sizes in px. */
const ICON_SIZE = SC.iconSizeMd;

export interface ShowcaseBottomNavProps {
  selected: ShowcaseNavTab;
  /**
   * Forces an arrangement instead of resolving it from the theme —
   * `AppBottomNavBar.formatOverride`. Null in normal use; the invariant test and
   * a side-by-side preview are its only readers.
   */
  formatOverride?: AppShellFormat | undefined;
}

export function ShowcaseBottomNav({ selected, formatOverride }: ShowcaseBottomNavProps) {
  const resolved = useFormat(FORMAT_SLOTS.appShell, APP_SHELL_FORMATS, 'stacked');
  const pill = (formatOverride ?? resolved) === 'markOnly';

  // Built ONCE, above the layout branch, so neither layout can drop, reorder or
  // duplicate a destination — the Dart file builds its `items` list the same way
  // and for the same reason.
  const items = TABS.map(({ tab, slot, label, Icon }) => (
    <NavItem
      key={tab}
      slot={slot}
      label={label}
      icon={<Icon />}
      isActive={tab === selected}
      showLabel={!pill}
    />
  ));

  if (pill) {
    // `NavFloatingPill` — an inset, rounded bar floating over the canvas. It
    // stays in the scaffold's bottom slot exactly as `NavFourUp` does (Dart
    // keeps both in `AppScreenScaffold`'s Column), so no screen and no scaffold
    // has to know which one is drawn.
    return (
      <div className={styles.pillInset}>
        <nav className={styles.pill} style={{ height: `${String(PILL_HEIGHT)}px` }}>
          {items}
        </nav>
      </div>
    );
  }

  return (
    // `NavFourUp`. Dart adds `MediaQuery.padding.bottom` here; the phone frame
    // publishes no bottom inset (its `MediaQuery` override is
    // `EdgeInsets.only(top:)`), so there is nothing to add.
    <nav className={styles.nav} style={{ height: `${String(ROW_HEIGHT)}px` }}>
      {items}
    </nav>
  );
}

interface NavItemProps {
  slot: string;
  label: string;
  icon: ReactElement;
  isActive: boolean;
  /**
   * `AppNavItem.showLabel`. When false the label is not laid out, but it is
   * still built and still announced — see `.visuallyHidden` in the stylesheet.
   */
  showLabel?: boolean;
}

function NavItem({ slot, label, icon, isActive, showLabel = true }: NavItemProps) {
  // `isActive ? accent : text2nd` — accent is the member app's selection /
  // active-state role, exactly as in `AppNavItem`. It is the ONLY active-state
  // affordance the Dart widget has, so there is no second class to toggle.
  const color = isActive ? 'var(--sc-accent)' : 'var(--sc-text-2nd)';
  return (
    <div className={styles.item} style={{ color }}>
      <ThemeIcon slot={slot} fallback={icon} color={color} size={ICON_SIZE} />
      <span className={cx(styles.label, !showLabel && styles.visuallyHidden)}>{label}</span>
    </div>
  );
}
