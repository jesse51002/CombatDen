/// One selectable app style: a customization **theme** (design/preset)
/// paired with the VideoService **feed** that goes with it. This curated
/// list — not the CustomizationService's full catalog — is the source of
/// truth for what the style picker (double-tap the home logo) offers, and
/// for which video feed the app pulls for the active theme.
///
/// The picker still fetches each design's display metadata (name +
/// celebration image) from the service, but only renders the designIds
/// that appear here. Add an entry to expose a new theme.
class AppStyle {
  const AppStyle({
    required this.designId,
    required this.videoAppId,
    this.videoBaseUrl = _kDefaultVideoBaseUrl,
  });

  /// The customization design/preset to load when this style is selected.
  final String designId;

  /// The VideoService `app_id` whose feed pairs with this theme. May differ
  /// from the customization appId/designId.
  final String videoAppId;

  /// Base URL of the VideoService deployment serving [videoAppId].
  final String videoBaseUrl;
}

/// Default VideoService base URL. Mirrors `CustomizationApiClient`: defaults
/// to localhost (use `adb reverse tcp:8002 tcp:8002` so a device reaches the
/// host over USB), overridable at launch with
/// `--dart-define=VIDEO_BASE_URL=http://<host-LAN-IP>:8002`.
const String _kDefaultVideoBaseUrl = String.fromEnvironment(
  'VIDEO_BASE_URL',
  defaultValue: 'http://localhost:8002',
);

/// The app's curated styles. None of these themes has its own generated feed
/// yet, so they all point at the `smoketest` feed for now — swap each
/// `videoAppId` to its real feed as they're generated. [AppConfig.designId]
/// (the default-loaded design) must stay represented here.
const List<AppStyle> kAppStyles = [
  AppStyle(designId: 'StrikeKickboxing', videoAppId: 'cardio_kickboxing'),
  AppStyle(designId: 'KillerMuayThai', videoAppId: 'muay_thai'),
  AppStyle(designId: 'ZenBJJ', videoAppId: 'bjj'),
  AppStyle(designId: 'ApexMMA', videoAppId: 'mma'),
  AppStyle(designId: 'FrictionGrappling', videoAppId: 'no_gi'),
  AppStyle(designId: 'SweetScienceBoxing', videoAppId: 'boxing'),
];

/// The curated style for [designId], or null when the design isn't one of
/// ours (→ no video feed for it).
AppStyle? appStyleForDesign(String designId) {
  for (final style in kAppStyles) {
    if (style.designId == designId) return style;
  }
  return null;
}
