/// The CombatDen app's customization slot manifest — the ONE
/// app-specific declaration of which slots this app expects.
///
/// Colours and images are handled identically: an explicit slot
/// id constant + an explicit `expected*` list. No dictionaries.
/// Adding a slot = add a `static const` id and one line to the
/// matching list here, plus `id` + `description` in the service
/// `apps/<app>/app.yaml`.
///
/// Colours are consumed via `DesignConstants` (which calls
/// `BrandColor.color(slot, fallback:)`); images via
/// `BrandImage.of(slot)` (a resolver returning an
/// `ImageProvider?`) — usually through the `BrandedImage`
/// widget, which pairs it with a bundled `ApiImage` fallback.
/// `ApiImage` itself is for live feature content and is fully
/// separate.
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
}
