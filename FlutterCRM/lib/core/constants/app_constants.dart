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

  AppConstants._();
}
