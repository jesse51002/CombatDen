/// Application-level constants that are not design
/// tokens.
class AppConstants {
  /// Maximum days since last class for green status
  /// dot.
  static const int lastClassThresholdRecent = 5;

  /// Maximum days since last class for amber status
  /// dot. Above this threshold, the dot turns red.
  static const int lastClassThresholdModerate = 14;

  /// Default number of rows per page for infinite
  /// scroll pagination.
  static const int defaultPageSize = 25;

  /// Responsive breakpoints for layout switching.
  static const double breakpointPhone = 600;
  static const double breakpointTablet = 900;
  static const double breakpointDesktop = 1200;

  /// The VideoService `template_gym` id seeded after login so the read-only
  /// content surfaces (Videos / Schedule / Loyalty / Dashboard classes) have a
  /// gym to render. The regular gym id (a UUID from `GET /api/v1/gyms/me`) and
  /// the VideoService `template_gym` id (a string like `boxing`) are **separate id
  /// spaces with no mapping**, so the real gym's UUID can't be used here — it
  /// 404s the VideoService. The Theme-tab gym picker overrides this. Override
  /// the default with `--dart-define=DEFAULT_VIDEO_GYM=<id>`.
  static const String defaultVideoGymId = String.fromEnvironment(
    'DEFAULT_VIDEO_GYM',
    defaultValue: 'boxing',
  );

  /// The platform default reward image — a wrapped-gift photo the backend
  /// applies to any reward created/updated without an image (`rewards
  /// .image_url` is NOT NULL). Previewed in the reward form so the owner sees
  /// exactly what a new reward gets before they upload their own. Kept in one
  /// place — never inline this URL at a call site.
  static const String defaultRewardImageUrl =
      'https://images.pexels.com/photos/5493207/pexels-photo-5493207.jpeg'
      '?auto=compress&cs=tinysrgb&w=1200';

  /// Curated default member portrait photos shown in the add/edit-member
  /// photo pool. Assets are uploaded post-curation via the preset uploader
  /// script; until then these URLs 404 and the field's Image.network
  /// errorBuilders render blank placeholders. Kept in one place — never
  /// inline these URLs at a call site.
  static const List<String> memberDefaultPhotoUrls = [
    'https://cdn.combatden.net/member/presets/portrait-01.jpg',
    'https://cdn.combatden.net/member/presets/portrait-02.jpg',
    'https://cdn.combatden.net/member/presets/portrait-03.jpg',
    'https://cdn.combatden.net/member/presets/portrait-04.jpg',
    'https://cdn.combatden.net/member/presets/portrait-05.jpg',
    'https://cdn.combatden.net/member/presets/portrait-06.jpg',
    'https://cdn.combatden.net/member/presets/portrait-07.jpg',
    'https://cdn.combatden.net/member/presets/portrait-08.jpg',
    'https://cdn.combatden.net/member/presets/portrait-09.jpg',
    'https://cdn.combatden.net/member/presets/portrait-10.jpg',
    'https://cdn.combatden.net/member/presets/portrait-11.jpg',
    'https://cdn.combatden.net/member/presets/portrait-12.jpg',
  ];

  /// Curated default activity photos shared by the membership-plan and class
  /// image pools. Assets are uploaded post-curation via the preset uploader
  /// script; until then these URLs 404 and the field's Image.network
  /// errorBuilders render blank placeholders. Kept in one place — never
  /// inline these URLs at a call site.
  static const List<String> activityDefaultImageUrls = [
    'https://cdn.combatden.net/membership/presets/activity-01.jpg',
    'https://cdn.combatden.net/membership/presets/activity-02.jpg',
    'https://cdn.combatden.net/membership/presets/activity-03.jpg',
    'https://cdn.combatden.net/membership/presets/activity-04.jpg',
    'https://cdn.combatden.net/membership/presets/activity-05.jpg',
    'https://cdn.combatden.net/membership/presets/activity-06.jpg',
    'https://cdn.combatden.net/membership/presets/activity-07.jpg',
    'https://cdn.combatden.net/membership/presets/activity-08.jpg',
    'https://cdn.combatden.net/membership/presets/activity-09.jpg',
    'https://cdn.combatden.net/membership/presets/activity-10.jpg',
    'https://cdn.combatden.net/membership/presets/activity-11.jpg',
    'https://cdn.combatden.net/membership/presets/activity-12.jpg',
  ];

  /// Curated default rank belt art (ten belt colors + five medallions) shown
  /// in the rank-edit belt-image pool. Assets are uploaded post-curation via
  /// the preset uploader script; until then these URLs 404 and the field's
  /// Image.network errorBuilders render blank placeholders. Kept in one
  /// place — never inline these URLs at a call site.
  static const List<String> rankBeltDefaultUrls = [
    'https://cdn.combatden.net/rank/presets/white.png',
    'https://cdn.combatden.net/rank/presets/gray.png',
    'https://cdn.combatden.net/rank/presets/yellow.png',
    'https://cdn.combatden.net/rank/presets/orange.png',
    'https://cdn.combatden.net/rank/presets/green.png',
    'https://cdn.combatden.net/rank/presets/blue.png',
    'https://cdn.combatden.net/rank/presets/purple.png',
    'https://cdn.combatden.net/rank/presets/brown.png',
    'https://cdn.combatden.net/rank/presets/red.png',
    'https://cdn.combatden.net/rank/presets/black.png',
    'https://cdn.combatden.net/rank/presets/medallion-01.png',
    'https://cdn.combatden.net/rank/presets/medallion-02.png',
    'https://cdn.combatden.net/rank/presets/medallion-03.png',
    'https://cdn.combatden.net/rank/presets/medallion-04.png',
    'https://cdn.combatden.net/rank/presets/medallion-05.png',
  ];

  AppConstants._();
}
