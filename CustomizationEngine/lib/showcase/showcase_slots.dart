/// The slot manifest the engine's own **showcase** screens consume.
///
/// This exists so a consumer that only wants the preview (e.g. the
/// AppManagement admin app) can pass `ShowcaseSlots.expected*` into
/// `CustomizationRuntime.initialize` WITHOUT importing any host app's
/// private manifest (MobileApp's `CombatDenSlots`). The ids match the
/// pipeline's wire keys, so the same loaded customization resolves
/// identically here and in the member app.
///
/// It is intentionally a *subset* — only the slots the four showcase
/// screens actually render — so the engine's startup slot-validation
/// warnings stay scoped to what the preview shows.
class ShowcaseSlots {
  ShowcaseSlots._();

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
  static const String celebrationImage = 'celebration_image';
  static const String streakIcon = 'streak_icon';
  static const String giftbox = 'giftbox';
  static const String singlePoint = 'single_point';
  static const String pointsStarsImage = 'points_stars_image';
  static const String trophyImage = 'trophy_image';
  static const String rankBelt = 'rank_belt';
  static const String iconQrcode = 'icon_qrcode';

  static const List<String> expectedImages = [
    logoPrimary,
    celebrationImage,
    streakIcon,
    giftbox,
    singlePoint,
    pointsStarsImage,
    trophyImage,
    rankBelt,
    iconQrcode,
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
  static const String bookNextClassCta = 'book_next_class_cta';
  static const String winsTitle = 'wins_title';
  static const String winsSubtitle = 'wins_subtitle';

  static const List<String> expectedText = [
    classBookedHeadline,
    reserveCta,
    bookNextClassCta,
    winsTitle,
    winsSubtitle,
  ];

  // ---- Icon slots ----
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
  static const String bookingCelebration = 'booking_celebration';
  static const String streakCelebration = 'streak_celebration';

  static const List<String> expectedLotties = [
    bookingCelebration,
    streakCelebration,
  ];
}
