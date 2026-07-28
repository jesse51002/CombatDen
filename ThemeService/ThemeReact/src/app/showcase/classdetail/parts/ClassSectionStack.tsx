// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/parts/class_section_stack.dart — the run of full-width sections, in
// whatever ORDER a layout hands them over, with the shipped gap and a rule
// between each pair.
//
// Owns the interleaving so three arrangements share one definition instead of
// each re-threading dividers through its own list. The order is the caller's:
// `bannerStack` runs meta -> details -> instructor -> location, `overlayHero`
// promotes the instructor above the description because at a combat gym the
// coach is the reason to book.

import type { ReactNode } from 'react';

import { cx } from '../../cx';

import styles from './ClassSectionStack.module.css';
import { SectionDivider } from './SectionDivider';

export interface ClassSectionStackProps {
  sections: readonly ReactNode[];
  /**
   * Whether to apply the screen's body inset. False when the caller already
   * sits inside one.
   */
  padded?: boolean;
}

export function ClassSectionStack({ sections, padded = true }: ClassSectionStackProps) {
  return (
    <div className={cx(styles.stack, padded && styles.padded)}>
      {sections.map((section, i) => (
        // Index keys: the section list is a FIXED, statically-ordered run per
        // arrangement — never reordered, filtered or appended at runtime — so
        // the index is a stable identity here rather than the usual smell.
        <div key={i} className={styles.item}>
          {i > 0 && <SectionDivider />}
          {section}
        </div>
      ))}
    </div>
  );
}
