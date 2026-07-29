/// The layout format enums: one per major screen, plus the shell that
/// frames every screen.
///
/// Each value is one complete, reviewed arrangement. Values are NOT
/// composable regions — a topbar enum crossed with a schedule enum
/// crossed with a hero enum would multiply what a human has to review
/// (4x4x4 = 64 home screens), and layout has no deterministic accept
/// condition to automate that review away. Whole-screen values keep the
/// count of things needing judgment equal to the count of things
/// shipped.
///
/// **The invariant every value must hold:** a format changes
/// ARRANGEMENT ONLY. No screen is merged or split, no functionality is
/// added, none is removed, and no variant reaches data the shipped
/// screen did not already have. `test/layout_invariants_test.dart`
/// enforces this mechanically by diffing the component multiset of each
/// variant against its baseline.
///
/// The first value of every enum is the arrangement that ships today
/// and is the parse fallback.
library;

import 'package:mobile_app/core/formats/format_parse.dart';

/// The chrome that frames every screen: topbar identity + stats, and the
/// bottom nav. Factored out of the per-screen enums because it belongs
/// to none of them and composes without changing any body.
enum AppShellFormat {
  /// Big square mark, name below, stats in a full-width bar.
  stacked,

  /// One row: mark leading, name centred, stats clustered trailing.
  compactRail,

  /// Stats promoted above identity.
  statFirst,

  /// Mark only, stats inline, floating pill nav. The gym name stays in
  /// the tree (a11y + switch target) but leaves the screen.
  markOnly;

  static AppShellFormat fromWire(String? wire) =>
      parseFormat(values, wire, AppShellFormat.stacked);
}

/// The class schedule.
enum HomeFormat {
  /// Pinned date rail over day groups; text left, thumb right.
  agendaList,

  /// One day per swipe; classes as wide media cards.
  dayPager,

  /// A time gutter runs the day; classes hang off their start time.
  timeSpine,

  /// Next class as a full-bleed hero; the rest goes dense.
  nextUpHero,

  /// Two-up card grid per day under a sticky day header.
  boardGrid;

  static HomeFormat fromWire(String? wire) =>
      parseFormat(values, wire, HomeFormat.agendaList);
}

/// The video feed.
enum VideosFormat {
  /// Featured hero over one horizontal row per tag.
  carouselRows,

  /// No horizontal scrolling; two large cards per tag then view-all.
  editorialStack,

  /// Featured spans two columns inside a mixed-size grid.
  mosaic,

  /// One column of tall cards with the tag overlaid on each.
  shortsColumn,

  /// Tags move to a scroll-spy rail; content is one column.
  tagRail;

  static VideosFormat fromWire(String? wire) =>
      parseFormat(values, wire, VideosFormat.carouselRows);
}

/// Rank and progress.
enum RankFormat {
  /// Streak hero, rank summary, next rank, level-up videos.
  sparkleStack,

  /// Belt takes the top with the streak over it, progress rail beneath.
  beltHero,

  /// A four-tile board opens the screen, graph runs full bleed beneath.
  statTiles,

  /// Next-rank progress becomes a large arc with the belt inside it.
  progressFirst,

  /// Now over next, graph collapsed onto the seam.
  splitRank;

  static RankFormat fromWire(String? wire) =>
      parseFormat(values, wire, RankFormat.sparkleStack);
}

/// The points store.
enum RewardsFormat {
  /// Two-up image-top cards with the price tag on the image.
  cardGrid,

  /// Full-width rows: square thumb left, action trailing.
  listRows,

  /// A snapping deck of posters with one action pinned beneath it.
  posterDeck,

  /// Banded by cost with the points total as an affordability bar.
  priceLadder,

  /// One promoted reward full bleed, the rest two-up beneath.
  storefrontHero;

  static RewardsFormat fromWire(String? wire) =>
      parseFormat(values, wire, RewardsFormat.cardGrid);
}

/// Class detail and booking.
enum ClassFormat {
  /// Banner, meta, then three divided sections; action pinned.
  bannerStack,

  /// Meta rides the image under a scrim; instructor promoted.
  overlayHero,

  /// Image is a fixed backdrop; content rises as a sheet.
  detailSheet,

  /// Details / instructor / location share one swipeable pane.
  sectionTabs,

  /// No banner: a spec table and an inline action.
  specBrief;

  static ClassFormat fromWire(String? wire) =>
      parseFormat(values, wire, ClassFormat.bannerStack);
}

/// The post-class celebration cards. One enum for all five (streak,
/// wins, points, rewards, rank): the body slot differs per card, the
/// arrangement around it does not.
enum CelebrationFormat {
  /// Everything centred, action pinned.
  centerHero,

  /// The earned figure top-aligned; illustration bleeds off the bottom.
  figureTop,

  /// Stat on a raised card, illustration breaking over its top edge.
  cardReveal,

  /// An illustration band over a plain lower half.
  splitBand,

  /// Illustration fills the screen; everything else stacks on a scrim.
  fullBleed;

  static CelebrationFormat fromWire(String? wire) =>
      parseFormat(values, wire, CelebrationFormat.centerHero);
}
