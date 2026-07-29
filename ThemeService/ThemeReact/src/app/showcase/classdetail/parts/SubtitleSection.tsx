// Ports ../../../../../../../MobileApp/lib/shared/widgets/subtitle_section.dart
// — an h2 title over its content. Three of the screen's four sections are one.
//
// Local to this screen rather than added to ../../support/: that folder is the
// ported CRM showcase chrome (scaffold, topbar, bottom nav, primary button) and
// is shared by every surface in the island, so a new file there is a change to
// everyone's chrome. This is one screen's section header.

import type { ReactNode } from 'react';

import { cx } from '../../cx';

import styles from './SubtitleSection.module.css';

/** `SubtitleSection.spacing` — `spacingLarge`, the Dart default. */
export type SubtitleSpacing = 'large' | 'medium';

export interface SubtitleSectionProps {
  title: string;
  children: ReactNode;
  /** The gap between the title and the content. Dart's default is `large`. */
  spacing?: SubtitleSpacing;
  className?: string | undefined;
  /** Marker + any other attributes the section's owner stamps on the root. */
  markerProps?: Record<string, string> | undefined;
}

export function SubtitleSection({
  title,
  children,
  spacing = 'large',
  className,
  markerProps,
}: SubtitleSectionProps) {
  return (
    <div
      className={cx(styles.section, spacing === 'medium' && styles.spacingMedium, className)}
      {...markerProps}
    >
      <h2 className={styles.title}>{title}</h2>
      {children}
    </div>
  );
}
