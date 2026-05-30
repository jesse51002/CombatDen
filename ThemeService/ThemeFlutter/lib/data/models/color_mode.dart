/// Light/dark target a resolved palette was generated for. Mirrors
/// ThemeService `schema/color_mode.py` (serialises "light" /
/// "dark"). Resilient per the MobileApp enum-parsing rule.
enum ColorMode {
  light,
  dark;

  bool get isLight => this == ColorMode.light;
  bool get isDark => this == ColorMode.dark;

  /// Defaults to [dark]: the bundled const-fallback palette is the
  /// dark CombatDen one, so an absent/unknown mode (old disk cache,
  /// malformed payload) stays consistent with the canvas the app
  /// actually renders when customization is unavailable.
  static ColorMode fromJson(Object? raw) {
    final name = raw is String ? raw.toLowerCase() : null;
    return ColorMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ColorMode.dark,
    );
  }

  String toJson() => name;
}
