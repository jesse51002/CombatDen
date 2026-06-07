import 'package:flutter/material.dart';

import 'package:crm/features/theme_browser/presentation/theme_browser_page.dart';
import 'package:crm/shared/themes/app_theme.dart';

/// Root of the standalone theme-browser app.
///
/// Reuses the admin [AppTheme.current] so the browser looks **identical** to the
/// embedded Theme tab — only the chrome around it differs (a top bar instead of
/// the admin nav rail). The browser is a **light-only** marketing surface
/// (matching the landing page): `main_theme_browser.dart` pins `themeController`
/// to [ThemeMode.light] at startup and never exposes the Settings control, so
/// `AppTheme.current` + every `DesignConstants` token resolves light here. No
/// routing table is needed: the page reads `?theme=…` off `Uri.base` directly,
/// so a plain `home:` is enough.
class ThemeBrowserApp extends StatelessWidget {
  const ThemeBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CombatDen Themes',
      theme: AppTheme.current,
      debugShowCheckedModeBanner: false,
      home: const ThemeBrowserPage(),
    );
  }
}
