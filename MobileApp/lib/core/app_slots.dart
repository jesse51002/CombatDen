/// The CombatDen app's customization slot manifest — the ONE
/// app-specific declaration of which slots this app expects.
///
/// Colours, images, fonts and texts are handled identically: an
/// explicit slot id constant + an explicit `expected*` list. No
/// dictionaries. Adding a slot = add a `static const` id and one
/// line to the matching list here, plus the matching declaration
/// in the service `apps/<app>/app.yaml`.
///
/// Colours are consumed via `DesignConstants` (which calls
/// `ThemeColor.color(slot, fallback:)`); images via
/// `ThemeImage.image(slot, fallback:)` at the call site.
/// Fonts are consumed via `ThemeFont.style(slot,
/// fallbackFamily:)`. Texts are consumed via
/// `ThemeText.value(slot, fallback:)`.
///
/// To retarget the engine for another app: write a sibling
/// manifest and change the wiring in `service_locator.dart`.
class CombatDenSlots {
  // Private constructor to prevent instantiation
  CombatDenSlots._();

  // ---- Colour slots ----
  static const String primary = 'primary';
  static const String background = 'background';
  static const String text = 'text';
  static const String accent = 'accent';

  static const List<String> expectedColors = [
    primary,
    background,
    text,
    accent,
  ];

  // ---- Image slots ----
  static const String logoPrimary = 'logo_primary';
  static const String rankBelt = 'rank_belt';
  static const String celebrationImage = 'celebration_image';
  static const String trophyImage = 'trophy_image';
  static const String pointsStarsImage = 'points_stars_image';
  static const String nextRankBeltImage = 'next_rank_belt_image';
  static const String giftbox = 'giftbox';
  static const String singlePoint = 'single_point';
  static const String iconQrcode = 'icon_qrcode';
  static const String streakIcon = 'streak_icon';

  static const List<String> expectedImages = [
    logoPrimary,
    rankBelt,
    celebrationImage,
    trophyImage,
    pointsStarsImage,
    nextRankBeltImage,
    giftbox,
    singlePoint,
    iconQrcode,
    streakIcon,
  ];

  // ---- Font slots ----
  static const String fontDisplay = 'display';
  static const String fontBody = 'body';

  static const List<String> expectedFonts = [
    fontDisplay,
    fontBody,
  ];

  // ---- Text slots ----
  static const String classBookedHeadline = 'class_booked_headline';
  static const String reserveCta = 'reserve_cta';
  static const String winsTitle = 'wins_title';
  static const String winsSubtitle = 'wins_subtitle';
  static const String bookNextClassCta = 'book_next_class_cta';

  static const List<String> expectedText = [
    classBookedHeadline,
    reserveCta,
    winsTitle,
    winsSubtitle,
    bookNextClassCta,
  ];

  // ---- Icon slots ----
  // The persistent bottom-nav tab icons. Consumed via `ThemeIcon.widget`
  // (slot + `Symbols.*_sharp` fallback) in `AppBottomNavBar`.
  static const String navHome = 'nav_home';
  static const String navRank = 'nav_rank';
  static const String navReward = 'nav_reward';
  static const String navVideos = 'nav_videos';

  static const List<String> expectedIcons = [
    navHome,
    navRank,
    navReward,
    navVideos,
  ];

  // ---- Lottie slots ----
  // The member-app booking celebration animation. Consumed via
  // `ThemeLottie` (slot + bundled `.json` fallback). The streak celebration
  // is now a pure-Flutter animation and no longer uses a Lottie slot.
  static const String bookingCelebration = 'booking_celebration';

  static const List<String> expectedLotties = [
    bookingCelebration,
  ];
}
