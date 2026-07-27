// Ports ../../../../../../CRM/lib/showcase/support/showcase_scaffold.dart —
// itself a clone of MobileApp's `AppScreenScaffold`. Background, safe-area,
// optional fixed topbar + bottom nav, and the horizontal inset for the body, so
// every showcase screen carries the exact member-app chrome.

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
}

export function ShowcaseScaffold({
  children,
  topbar,
  bottomNav,
  horizontalPadding = 'standard',
  backgroundColor,
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
      <div className={cx(styles.body, paddingClass(horizontalPadding))}>{children}</div>
      {bottomNav}
    </div>
  );
}
