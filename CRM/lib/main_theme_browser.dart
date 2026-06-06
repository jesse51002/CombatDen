import 'package:flutter/material.dart';

import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/theme_browser/presentation/theme_browser_app.dart';

/// Standalone entry point for the **public theme browser** deployment.
///
/// Same project as the admin app (`main.dart`), different build `--target`: this
/// boots only the theme browser, full-screen, with a landing-style top bar. It
/// reuses the very same `LiveThemePreviewTab` module the admin Theme tab embeds,
/// so the browser is never rewritten twice.
///
/// Run with `make run-themes`, build with `make build-themes`, deploy with
/// `make deploy-themes` (themes.combatden.net). See AppManagement/CLAUDE.md.
void main() {
  // The theme browser is a light-only marketing surface (it matches the landing
  // page and never shows the admin Settings control). Pin the shared
  // [themeController] to light so every `DesignConstants` token resolves light
  // here regardless of the visitor's OS dark-mode setting.
  themeController.setMode(ThemeMode.light);
  runApp(const ThemeBrowserApp());
}
