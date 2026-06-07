/// Tunable constants for the gym setup poller.
abstract class GymSetupConstants {
  /// Cadence between successful polls.
  static const Duration pollInterval = Duration(seconds: 10);

  /// Backoff schedule after consecutive poll errors.
  static const Duration errorBackoff1 = Duration(seconds: 15);
  static const Duration errorBackoff2 = Duration(seconds: 30);
  static const Duration errorBackoffMax = Duration(seconds: 60);

  /// Safety margin when checking whether a hosted
  /// Stripe URL is about to expire.
  static const Duration linkExpiryBuffer =
      Duration(seconds: 10);

  /// Show the "having trouble reaching the server"
  /// banner after this many consecutive poll errors.
  static const int bannerThresholdErrors = 2;
}
