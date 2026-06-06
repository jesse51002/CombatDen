import 'package:flutter/material.dart';

/// Parse the backend `theme_mode` string (`system` / `light` / `dark`) into
/// Flutter's [ThemeMode]. Falls back to [ThemeMode.system] for any unknown
/// value, per the resilient-enum rule — a new backend value never crashes.
ThemeMode themeModeFromApi(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

/// Serialize Flutter's [ThemeMode] back to the backend `theme_mode` string.
String themeModeToApi(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

/// The app-wide CRM **appearance** state — light / dark / follow-OS.
///
/// A plain global [ChangeNotifier], the same shape as [selectedGym]: surfaces
/// watch it with `ListenableBuilder(listenable: themeController, ...)`. It is
/// the single source of truth the design system swaps on — every
/// `DesignConstants` color token resolves through [isDark], so the whole app
/// re-skins on a mode change without any widget reading `Theme.of(context)`.
///
/// The chosen [mode] is hydrated at login from the caller's `gym_employees`
/// row and saved back through the FastApiBackend when the Settings control
/// changes it (see `features/settings/`). [setPlatformBrightness] keeps the
/// `system` mode live as the OS flips between light and dark.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  Brightness _platformBrightness = Brightness.light;

  /// The chosen mode (what the Settings control shows selected).
  ThemeMode get mode => _mode;

  /// Whether the app should paint dark right now — the value every
  /// `DesignConstants` color token branches on. For [ThemeMode.system] this
  /// follows the OS brightness ([setPlatformBrightness]).
  bool get isDark => switch (_mode) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system => _platformBrightness == Brightness.dark,
      };

  /// Apply the saved preference loaded at login (no persistence write).
  void hydrate(ThemeMode mode) => setMode(mode);

  /// Change the mode in-session (the Settings control). Persisting the choice
  /// to the backend is the caller's responsibility (optimistic update).
  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Feed the current OS brightness (from `main`'s binding observer) so a
  /// `system`-mode app flips the instant the OS theme changes.
  void setPlatformBrightness(Brightness brightness) {
    if (_platformBrightness == brightness) return;
    _platformBrightness = brightness;
    if (_mode == ThemeMode.system) notifyListeners();
  }
}

/// The one process-wide appearance controller, watched by the app root and the
/// Settings control.
final ThemeController themeController = ThemeController();
