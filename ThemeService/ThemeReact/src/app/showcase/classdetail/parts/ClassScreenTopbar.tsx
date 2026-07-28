// Ports ../../../../../../../MobileApp/lib/features/class_booking/presentation/
// layouts/parts/class_screen_topbar.dart — the class screen's topbar, defined
// ONCE for all five arrangements.
//
// Shared rather than repeated so no arrangement can quietly ship a different
// topbar, or lose the BACK CONTROL — which is the only way off this screen that
// does not commit to a booking. `class_invariants_test.dart` counts both.
//
// COMPOSED, NOT REBUILT. The identity + stats bar is ../../support/
// ShowcaseTopbar.tsx in its `nameOnly` mode, exactly as the Dart passes
// `AppTopbarMode.nameOnly`. What that shared component has no counterpart for
// is `showBackButton: true` — no other showcase screen is reachable from
// another screen, so the preview's topbar never needed one. Rather than change
// a component every surface in the island shares, the chevron sits BESIDE it as
// a leading gutter, which is the same shape `AppTopbar` has: a leading slot,
// then the bar. The tap is a preview no-op, like every other tap in this island.
//
// A GUTTER RATHER THAN AN OVERLAY, and that is load-bearing. `ShowcaseTopbar`
// resolves `app_shell_format` into four arrangements whose heights and internal
// alignment all differ — `stacked` is a column, `compactRail` a row, `compact`
// trims its own padding — so any absolute offset chosen against one of them is
// wrong for the other three. It also has no leading gutter of its own, so an
// overlaid chevron lands on the gym name in every arrangement that left-aligns
// it. A flex sibling is height-agnostic and cannot collide: the chevron centres
// against whatever the bar turns out to be.
//
// The bar's own bottom hairline therefore starts after the chevron rather than
// running the full width. Deliberate: the rule belongs to `ShowcaseTopbar`, and
// three of the four shell arrangements draw it while `markOnly` suppresses it.
// Drawing a matching stub here would contradict that arrangement's own choice
// the moment a tenant classified into it.

import { ShowcaseTopbar } from '../../support/ShowcaseTopbar';
import { CLASS_PART, classPart } from '../classParts';

import styles from './ClassScreenTopbar.module.css';

/**
 * The demo stats the info bar carries. Same values ../../home/HomeShowcase.tsx
 * uses, so the two surfaces agree in one slideshow.
 */
const RANK_BADGE_ASSET = 'icon_rank_belt.png' as const;
const STREAK_DAYS = 3;
const POINTS_LABEL = '3.4k';

export interface ClassScreenTopbarProps {
  gymName: string;
  /** The host gym's real logo URL. Absent in the public browser. */
  gymLogoSrc?: string | undefined;
  themeTabPreview?: boolean | undefined;
}

export function ClassScreenTopbar({
  gymName,
  gymLogoSrc,
  themeTabPreview = true,
}: ClassScreenTopbarProps) {
  return (
    <div className={styles.topbar} {...classPart(CLASS_PART.topbar)}>
      <BackButton />
      <div className={styles.bar}>
        <ShowcaseTopbar
          mode="nameOnly"
          gymName={gymName}
          logoSrc={gymLogoSrc}
          streakDays={STREAK_DAYS}
          pointsLabel={POINTS_LABEL}
          rankBadgeAsset={RANK_BADGE_ASSET}
          themeTabPreview={themeTabPreview}
        />
      </div>
    </div>
  );
}

/**
 * `TopbarBackButton` — `Icon(chevron_left_sharp, size: iconSize2xl,
 * color: text)` inside `EdgeInsets.all(spacingMedium)`.
 *
 * Drawn here rather than added to ../../support/icons.tsx: that file is the
 * shared member-app glyph set and every surface in the island reads it, so a
 * new export there is a change to everyone's icons. Same 24-unit box and the
 * same `iconWeight` 300 -> 1.5px stroke that file documents, so the chevron
 * matches the rest of the set exactly.
 */
function BackButton() {
  return (
    <button type="button" className={styles.back} aria-label="Back" {...classPart(CLASS_PART.back)}>
      <svg
        className={styles.backIcon}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
        focusable="false"
      >
        <path d="M15 5.5 L8.5 12 L15 18.5" />
      </svg>
    </button>
  );
}
