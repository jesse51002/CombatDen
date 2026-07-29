// Ports ../../../../../../CRM/lib/showcase/support/showcase_scaffold.dart —
// itself a clone of MobileApp's `AppScreenScaffold`. Background, safe-area,
// optional fixed topbar + bottom nav, and the horizontal inset for the body, so
// every showcase screen carries the exact member-app chrome.
//
// SCROLLING IS OPT-IN PER SCREEN (`bodyScroll`), NOT A GLOBAL FLIP, and the
// reason is a CSS rule rather than a preference. When one of `overflow-x` /
// `overflow-y` is `visible` and the other is not, the `visible` one COMPUTES to
// `auto` — so turning the body into a vertical scroller silently makes it clip
// horizontally too. Four surfaces in this island paint deliberately outside
// their box (../celebrations/SparkleBurst.tsx, ../celebrations/RewardsCarousel.tsx's
// cover flow, ../rewards/SparkleHero.tsx's scatter), and a global
// `overflow-y: auto` would have cropped every one of them. The screens that
// want depth ask for it; the celebrations do not, and keep their overflow.

import type { ReactNode } from 'react';

import { cx } from '../cx';

import styles from './ShowcaseScaffold.module.css';

/** Horizontal-padding variant — `ShowcasePadding` / `AppScreenHorizontalPadding`. */
export type ShowcasePadding = 'standard' | 'big' | 'none';

function paddingClass(variant: ShowcasePadding): string | undefined {
  if (variant === 'standard') return styles.padStandard;
  if (variant === 'big') return styles.padBig;
  return undefined;
}

export interface ShowcaseScaffoldProps {
  children: ReactNode;
  topbar?: ReactNode;
  bottomNav?: ReactNode;
  horizontalPadding?: ShowcasePadding | undefined;
  /** CSS colour. Defaults to `var(--sc-background)`. */
  backgroundColor?: string | undefined;
  /**
   * Scroll the body vertically, as the app-shaped screens do on a real device
   * (`SingleChildScrollView` / `CustomScrollView`). OFF by default: it also
   * makes the body clip horizontally (see the header), which is exactly wrong
   * for the celebration surfaces that paint outside their box.
   */
  bodyScroll?: boolean | undefined;
}

export function ShowcaseScaffold({
  children,
  topbar,
  bottomNav,
  horizontalPadding = 'standard',
  backgroundColor,
  bodyScroll = false,
}: ShowcaseScaffoldProps) {
  // `SafeArea(top: !hasTopNav, bottom: !hasBottomNav)`. The frame publishes its
  // status inset as `--phone-status-inset` (../../widgets/PhoneFrame.tsx) where
  // Dart overrides the child's `MediaQuery.padding.top`; there is deliberately
  // no bottom counterpart, because the Dart frame sets `EdgeInsets.only(top:)`
  // and leaves the bottom inset at zero.
  const safeTop = topbar === undefined || topbar === null;

  return (
    <div
      className={styles.scaffold}
      style={backgroundColor === undefined ? undefined : { background: backgroundColor }}
    >
      {safeTop && <div className={styles.safeTop} />}
      {topbar}
      <div
        className={cx(styles.body, bodyScroll && styles.bodyScroll, paddingClass(horizontalPadding))}
      >
        {children}
      </div>
      {bottomNav}
    </div>
  );
}
