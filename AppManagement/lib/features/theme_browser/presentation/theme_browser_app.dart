import 'package:flutter/material.dart';

import 'package:app_management/features/theme_browser/presentation/theme_browser_page.dart';
import 'package:app_management/shared/themes/app_theme.dart';

/// Root of the standalone theme-browser app.
///
/// Reuses the admin [AppTheme.light] so the browser looks **identical** to the
/// embedded Theme tab — only the chrome around it differs (a top bar instead of
/// the admin nav rail). No routing table is needed: the page reads `?theme=…`
/// off `Uri.base` directly, so a plain `home:` is enough.
class ThemeBrowserApp extends StatelessWidget {
  const ThemeBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CombatDen Themes',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const ThemeBrowserPage(),
    );
  }
}
