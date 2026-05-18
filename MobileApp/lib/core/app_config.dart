/// App-level configuration. This is the APP's identity — NOT
/// part of the customization package. It declares which tenant
/// app and which design (preset/run) this build targets; those
/// values are passed into `CustomizationRuntime.initialize`.
///
/// The customization service URL and request path are internal
/// to the customization package and intentionally NOT here.
class AppConfig {
  // Private constructor to prevent instantiation
  AppConfig._();

  /// Tenant app identifier (snake_case).
  static const String appId = 'combatden';

  /// The design (preset/run) of [appId] to load.
  static const String designId = 'bjj';
}
