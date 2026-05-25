/// Hardcoded theme presets for the Member App "Theme" tab.
///
/// Mirrors the member app's style picker (double-tap the home logo):
/// each preset is a curated design with a celebration hero image and a
/// display name. Field names match what the CustomizationService's
/// `GET /apps/{appId}/styles` endpoint will eventually return, so the
/// swap to real data stays mechanical.
library;

class AppThemeOption {
  /// The customization design id (e.g. `ApexMMA`). Stable wire value.
  final String id;

  /// Human-readable name shown under the hero art.
  final String displayName;

  /// Local celebration image bundled in `assets/images/`.
  final String celebrationImageAsset;

  const AppThemeOption({
    required this.id,
    required this.displayName,
    required this.celebrationImageAsset,
  });
}

/// The design id of the theme the member app is currently wearing.
const String kActiveThemeId = 'ApexMMA';

/// The curated presets the admin can pick from. Same six the member app
/// exposes in its style picker.
const List<AppThemeOption> kMockAppThemes = [
  AppThemeOption(
    id: 'StrikeKickboxing',
    displayName: 'Strike Kickboxing',
    celebrationImageAsset: 'assets/images/theme_strike_kickboxing.png',
  ),
  AppThemeOption(
    id: 'KillerMuayThai',
    displayName: 'Killer Muay Thai',
    celebrationImageAsset: 'assets/images/theme_killer_muay_thai.png',
  ),
  AppThemeOption(
    id: 'ZenBJJ',
    displayName: 'Zen BJJ',
    celebrationImageAsset: 'assets/images/theme_zen_bjj.png',
  ),
  AppThemeOption(
    id: 'ApexMMA',
    displayName: 'Apex MMA',
    celebrationImageAsset: 'assets/images/theme_apex_mma.png',
  ),
  AppThemeOption(
    id: 'FrictionGrappling',
    displayName: 'Friction Grappling',
    celebrationImageAsset: 'assets/images/theme_friction_grappling.png',
  ),
  AppThemeOption(
    id: 'SweetScienceBoxing',
    displayName: 'Sweet Science Boxing',
    celebrationImageAsset: 'assets/images/theme_sweet_science_boxing.png',
  ),
];
