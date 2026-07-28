// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// widgets/class_reserve_footer.dart — the primary "Reserve your spot" CTA and
// its separating rule.
//
// THE SCREEN COMMITS IN EXACTLY ONE PLACE. `ClassReservePosition` moves that
// place; no value adds a second one. A layout that repeated the CTA "for
// convenience" would change the screen's CONTRACT — one commit point — rather
// than its arrangement, and .../__tests__/classFormats.test.tsx fails if one
// tries, counting the button through the whole tree so a duplicate parked
// behind a tab counts too.
//
// The label is the theme's `reserve_cta` TEXT SLOT. The slot has been in
// ../../showcaseSlots.ts (and in the engine's `expectedText` list) since the
// island was built, but no preview screen rendered it until this one — the
// pipeline generated a value for all 76 themes that the browser then never
// showed. This is its first consumer here, exactly as Profile was
// `next_rank_belt_image`'s.

import { useThemeText } from 'theme-react';

import { cx } from '../../cx';
import { SLOT_RESERVE_CTA } from '../../showcaseSlots';
import { ShowcasePrimaryButton } from '../../support/ShowcasePrimaryButton';
import { CLASS_PART, classPart } from '../classParts';
import { SectionDivider } from '../parts/SectionDivider';

import styles from './ClassReserveFooter.module.css';

/**
 * `ClassReservePosition` — where a layout puts the one reserve action.
 *
 *   * `pinned`   — under the scrolling body, rule above. Ships today.
 *   * `sheetTop` — at the top of a sheet, rule BELOW: the action arrives on
 *     the way down instead of at the end of a scroll.
 *   * `inline`   — in the content flow, at the end of it. Carries no side
 *     padding because the content column already supplies it.
 */
export type ClassReservePosition = 'pinned' | 'sheetTop' | 'inline';

// See ./ClassImageBanner.tsx on the `| undefined`.
const POSITION_CLASS: Readonly<Record<ClassReservePosition, string | undefined>> = {
  pinned: styles.pinned,
  sheetTop: styles.sheetTop,
  inline: styles.inline,
};

export interface ClassReserveFooterProps {
  /** Defaults to `pinned`, the position that ships. */
  position?: ClassReservePosition;
}

export function ClassReserveFooter({ position = 'pinned' }: ClassReserveFooterProps) {
  const label = useThemeText(SLOT_RESERVE_CTA, 'Reserve your spot');
  const action = (
    <div className={cx(styles.action, POSITION_CLASS[position])}>
      <div {...classPart(CLASS_PART.reserveButton)}>
        <ShowcasePrimaryButton text={label} fullWidth borderRadius="var(--sc-radius-big)" />
      </div>
    </div>
  );

  return (
    <div className={styles.footer} {...classPart(CLASS_PART.reserve)}>
      {/* `sheetTop` puts the rule BELOW the action; the other two above it. */}
      {position === 'sheetTop' ? (
        <>
          {action}
          <SectionDivider />
        </>
      ) : (
        <>
          <SectionDivider />
          {action}
        </>
      )}
    </div>
  );
}
