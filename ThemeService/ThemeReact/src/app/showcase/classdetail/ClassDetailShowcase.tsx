// Ports ../../../../../../MobileApp/lib/features/class_booking/presentation/
// screens/class_screen.dart — the class DETAIL / booking screen, and the only
// consumer of the `class_format` slot.
//
// NOT TO BE CONFUSED WITH ../BookingShowcase.tsx, which is the other screen in
// the same Dart feature folder. That one clones `ClassBookedScreen`, the
// post-reservation CELEBRATION (image pop, caption cascade, CTA fade, loop) and
// is governed by NO format slot at all. `ClassFormat` governs THIS screen —
// `ThemeLayout.classDetail()` is read in exactly one place, `class_screen.dart`
// — and the two surfaces share only a folder name and the word "booking".
// Reshaping the celebration into a detail page would have deleted an animation
// the preview relies on, which is why this is a tenth screen rather than a
// rework of the second.
//
// THE ARRANGEMENT IS RESOLVED FROM THE TENANT'S `class_format` SLOT and
// delegated to one of ./layouts/, each of which composes the same sections from
// ./sections/. Every layout renders the same element set — topbar, back control,
// photo, meta, details, instructor, location, and exactly ONE reserve action —
// and ../__tests__/classFormats.test.tsx proves it for all five values.
//
// WHAT DOES NOT PORT, and why it is absent rather than missing. The Dart screen
// owns two hooks this browser has no host for: the capture harness's scroll
// controller + two `GlobalKey`s (`tools/capture/` drives them; there is no
// harness here), and a horizontal swipe into the post-class flow
// (`Navigator.pushReplacementNamed`; there is no router here, and the
// slideshow's own next-screen arrows belong to ../../browser/, which this
// island may not import — eslint.config.js Gate 2a). Porting either as a dead
// handler would invent an affordance the preview cannot honour. The swipe that
// IS real — `sectionTabs`'s tab change — is ported in full, and the test's
// swipe group asserts the adapted contract with the Dart's own numbers recorded
// beside it.
//
// THE SCREEN DOES NOT SCROLL AS A WHOLE; each arrangement owns its own
// scroller, exactly as the Dart's five do. So `ShowcaseScaffold` is given no
// `bodyScroll` and keeps its `overflow: hidden` — the layouts opt in, which is
// also what keeps `detailSheet`'s backdrop from being clipped by an ancestor
// scroller it never asked for.
//
// THE FOLDER IS `sections/`, WHERE THE DART SAYS `widgets/`, and the rename is
// forced rather than stylistic: eslint.config.js Gate 2a bans `**/widgets/**`
// from anywhere in this island, because `src/app/widgets/` is the surrounding
// ADMIN chrome and carries the same token names with different values. The
// gate matches the IMPORT STRING, so `../widgets/ClassMetaSection` trips it
// even though the target is this screen's own folder. `sections/` also happens
// to be what the Dart calls them everywhere but the folder name — "the four
// content sections", `ClassSectionStack`, `class_section_tabs`.

import { CLASS_FORMATS, FORMAT_SLOTS, useFormat } from '../formats';
import type { ShowcaseClassInfo } from '../showcaseContent';
import { ShowcaseScaffold } from '../support/ShowcaseScaffold';

import { detailFor, previewClassCard } from './classDetail';
import { ClassBannerStack } from './layouts/ClassBannerStack';
import { ClassDetailSheet } from './layouts/ClassDetailSheet';
import { ClassOverlayHero } from './layouts/ClassOverlayHero';
import { ClassSectionTabs } from './layouts/ClassSectionTabs';
import { ClassSpecBrief } from './layouts/ClassSpecBrief';
import type { ClassLayoutProps } from './layouts/layoutProps';

export interface ClassDetailShowcaseProps {
  gymName?: string;
  /** The host gym's real logo URL. Absent in the public browser. */
  gymLogoSrc?: string | undefined;
  /** The gym's real classes; null falls back to the group defaults. */
  classes?: readonly ShowcaseClassInfo[] | null;
  /**
   * The previewed style's showcase category. Needed because the detail-only
   * text resolves PER FIELD against the bundled group (./classDetail.ts), not
   * only through the tier `useShowcaseContent` already picked.
   */
  category?: string | null;
}

export function ClassDetailShowcase({
  gymName = 'Your Gym',
  gymLogoSrc,
  classes,
  category = null,
}: ClassDetailShowcaseProps) {
  // `ThemeLayout.classDetail()` — the preview override, then the theme's
  // classified pick, then the value that ships.
  const format = useFormat(FORMAT_SLOTS.class, CLASS_FORMATS, 'bannerStack');
  const detail = detailFor(previewClassCard(classes, category), gymName);
  const props: ClassLayoutProps = { detail, gymName, gymLogoSrc };

  // `_layout`'s switch, exhaustive over the vocabulary.
  let layout;
  switch (format) {
    case 'bannerStack':
      layout = <ClassBannerStack {...props} />;
      break;
    case 'overlayHero':
      layout = <ClassOverlayHero {...props} />;
      break;
    case 'detailSheet':
      layout = <ClassDetailSheet {...props} />;
      break;
    case 'sectionTabs':
      layout = <ClassSectionTabs {...props} />;
      break;
    case 'specBrief':
      layout = <ClassSpecBrief {...props} />;
      break;
  }

  // `AppScreenScaffold(horizontalPadding: none)` — every arrangement is
  // edge-to-edge and supplies its own inset. No topbar / bottomNav props: the
  // topbar is rendered INSIDE each layout (the arrangements place it
  // differently, and two of them lay it over the photo), and the class detail
  // screen carries no bottom nav in the member app either.
  return <ShowcaseScaffold horizontalPadding="none">{layout}</ShowcaseScaffold>;
}
