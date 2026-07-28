// No Dart counterpart — this is the web's stand-in for `find.byType(...)`.
//
// `MobileApp/test/videos_invariants_test.dart` proves the arrangement-only
// invariant by counting WIDGET TYPES in the rendered tree: one
// `FeaturedVideoCard`, one `VideoCarouselSection` per tag, one
// `VideoViewAllAction` per tag, a `VideoCarouselCard` for every video. React
// has no equivalent — a rendered tree is DOM, and a CSS-module class name is a
// build-time hash that says nothing about which component wrote it — so each
// ported component stamps its identity onto its root element as
// `data-sc-part`, and ./__tests__/videosFormats.test.tsx diffs the multiset of
// those across all five arrangements.
//
// They are INSTRUMENTATION, not styling: no stylesheet in this island selects
// on them, and the baseline assertion in that test strips them before comparing
// the shipped arrangement's markup, so the attribute cannot drift into being
// load-bearing markup.

/** The attribute each ported videos component stamps its identity on. */
export const PART_ATTR = 'data-sc-part';

/** One value per component whose count the invariant pins. */
export const VIDEO_PARTS = Object.freeze({
  /** `VideoCategoryTabs` — the top filter, whatever axis it runs on. */
  categoryTabs: 'category-tabs',
  /** `_CategoryPill` — "All" plus one per genre. */
  categoryPill: 'category-pill',
  /** `FeaturedVideoCard` — the hero. */
  featured: 'featured-video',
  /** The hero's `AppPrimaryButton` "Play" action. */
  featuredPlay: 'featured-play',
  /** `VideoReccCard` — the shared recommendation card inside the hero. */
  reccCard: 'recc-card',
  /** `VideoCarouselSection` — one per genre. */
  section: 'video-section',
  /** `VideoSectionHeader`'s title. */
  sectionTitle: 'section-title',
  /** `VideoViewAllAction` — one per section, in whichever treatment. */
  viewAll: 'view-all',
  /** `VideoCarouselCard` — one per video. */
  card: 'video-card',
  /** Every rendered thumbnail. */
  thumb: 'video-thumb',
  /** Every rendered creator avatar (absent by design when the URL is blank). */
  avatar: 'creator-avatar',
  /** `VideosFeedStatus` — the reason there is nothing to arrange. */
  feedStatus: 'feed-status',
});
