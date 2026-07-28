// The element-set contract for `class_format`, and the marker every
// arrangement stamps so it can be counted.
//
// WHY THIS FILE EXISTS. Flutter's functional-equivalence gate
// (`MobileApp/test/class_invariants_test.dart`) counts WIDGET TYPES —
// `find.byType(ClassMetaSection)` — because a Dart element tree carries the
// type of every node. A rendered React tree does not: by the time it is DOM
// there is no `ClassMetaSection` left to find, only divs. So the countable
// identity is stamped explicitly, as a `data-class-part` attribute on each
// section's root, and both the sections and the test read the vocabulary from
// here. One definition means a renamed marker cannot silently stop being
// counted — the test would fail to find it rather than quietly pass on zero.
//
// THE CONTRACT ITSELF: every arrangement renders EXACTLY ONE of each of these,
// and `.../__tests__/classFormats.test.tsx` proves it for all five values.
// A format may move an element and change its prominence; it may not drop one
// and it may not add a second. That is what makes a format an ARRANGEMENT
// rather than a different screen.

/** The stamped attribute. One name, so the query and the render cannot drift. */
export const PART_ATTR = 'data-class-part';

/**
 * The element set every `class_format` value must carry exactly once.
 *
 * Mirrors the `expectExactlyOne` calls in the Dart gate one for one:
 * topbar + back control (the only way off the screen that does not commit),
 * the photo, the four content sections, and the single reserve action.
 */
export const CLASS_PART = Object.freeze({
  /** `AppTopbar`. */
  topbar: 'topbar',
  /** `TopbarBackButton`. */
  back: 'back',
  /** `ClassImageBanner` — never dropped; `specBrief` shrinks it to a thumb. */
  banner: 'banner',
  /** `ClassMetaSection`. */
  meta: 'meta',
  /** `ClassDetailsSection`. */
  details: 'details',
  /** `ClassInstructorSection`. */
  instructor: 'instructor',
  /** `ClassLocationSection`. */
  location: 'location',
  /** `ClassReserveFooter`. */
  reserve: 'reserve',
  /** `AppPrimaryButton` inside the footer — the ONE commit point. */
  reserveButton: 'reserve-button',
});

/** One of the marker values. */
export type ClassPart = (typeof CLASS_PART)[keyof typeof CLASS_PART];

/**
 * Spreadable marker props. `<div {...classPart(CLASS_PART.meta)}>` reads at
 * the call site as "this is the meta section", which is the point.
 */
export function classPart(part: ClassPart): Record<string, string> {
  return { [PART_ATTR]: part };
}
