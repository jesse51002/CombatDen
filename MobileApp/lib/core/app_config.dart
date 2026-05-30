/// App-level configuration. This is the APP's identity — NOT
/// part of the customization package. It declares which tenant
/// app and which design (preset/run) this build targets; those
/// values are passed into `ThemeRuntime.initialize`.
///
/// The customization service URL and request path are internal
/// to the customization package and intentionally NOT here.
class AppConfig {
  // Private constructor to prevent instantiation
  AppConfig._();

  /// Tenant app identifier (snake_case).
  static const String appId = 'combatden';

  /// The design the customization runtime initializes on, only so it has
  /// something to fetch for the first paint (the gym-select screen). It is NOT
  /// a selected gym — content (videos / classes / rewards) follows the gym the
  /// user picks on the gym-select screen ([SelectedGym]); there is no hardcoded
  /// gym anymore.
  static const String designId = 'StrikeKickboxing';
}
