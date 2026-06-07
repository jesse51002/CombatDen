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

  /// The VideoService `video_gym` id seeded after login so the read-only
  /// content surfaces (Videos / Schedule / Loyalty / Dashboard classes) have a
  /// gym to render. The regular gym id (a UUID from `GET /api/v1/gyms/me`) and
  /// the VideoService `video_gym` id (a string like `boxing`) are **separate id
  /// spaces with no mapping**, so the real gym's UUID can't be used here — it
  /// 404s the VideoService. The Theme-tab gym picker overrides this. Override
  /// the default with `--dart-define=DEFAULT_VIDEO_GYM=<id>`.
  static const String defaultVideoGymId = String.fromEnvironment(
    'DEFAULT_VIDEO_GYM',
    defaultValue: 'boxing',
  );

  AppConstants._();
}
